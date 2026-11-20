package com.androidlink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.telephony.SmsManager
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.net.DatagramPacket
import java.util.concurrent.Executors
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.TimeUnit

/**
 * Foreground service that owns the encrypted link to the Mac.
 * Lives independently of the Flutter UI: SMS / calls / notifications keep
 * flowing when the app is closed. Discovery = UDP beacon from the Mac;
 * transport = WebSocket; every frame is AES-GCM with the key from QR pairing.
 */
class LinkService : Service() {

    companion object {
        private const val TAG = "LinkService"
        private const val CHANNEL_ID = "link"
        private const val NOTIF_ID = 1
        private const val UDP_PORT = 41235
        private const val MAX_QUEUE = 300
        const val ACTION_RECONNECT = "com.androidlink.RECONNECT"

        @Volatile var instance: LinkService? = null
            private set

        /** "unpaired" | "searching" | "connecting" | "connected" | "unauthorized" */
        @Volatile var status: String = "unpaired"
            private set

        /** Human-readable diagnostics for the UI (why we can't connect). */
        @Volatile var diag: String = ""
            private set
        @Volatile var lastBeacon: Long = 0
            private set
        @Volatile var lastHost: String = ""
            private set

        /** UI listeners: (kind, data). kind = "status" | "message". */
        val listeners = CopyOnWriteArraySet<(String, Any) -> Unit>()

        private val pending = ArrayDeque<Pair<String, JSONObject>>()

        fun start(ctx: Context, action: String? = null) {
            if (!LinkPrefs(ctx).isPaired) return
            val i = Intent(ctx, LinkService::class.java).setAction(action)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            } catch (e: Exception) {
                Log.w(TAG, "start failed: ${e.message}")
            }
        }

        fun stop(ctx: Context) = ctx.stopService(Intent(ctx, LinkService::class.java))

        /** Send an event to the Mac from anywhere (receivers, listener service, UI). */
        fun post(ctx: Context, type: String, payload: JSONObject) {
            val s = instance
            if (s != null) { s.send(type, payload); return }
            synchronized(pending) {
                pending.addLast(type to payload)
                while (pending.size > MAX_QUEUE) pending.removeFirst()
            }
            start(ctx)
        }
    }

    private lateinit var prefs: LinkPrefs
    lateinit var files: FileTransfer
        private set
    private var smsObserver: PhoneData.SmsObserver? = null
    private var mmsObserver: Mms.Observer? = null
    private val io = Executors.newSingleThreadExecutor()
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private val main = Handler(Looper.getMainLooper())

    private val http = OkHttpClient.Builder()
        .pingInterval(15, TimeUnit.SECONDS)
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    // All fields below are touched only on `handler` thread.
    private var ws: WebSocket? = null
    private var wsHost: String? = null
    private var authed = false
    private var phoneSid = ""
    private var macSid = ""
    private var attempt = 0
    private val queue = ArrayDeque<Pair<String, JSONObject>>()
    private var lastBattery = -1
    private var lastCharging = false

    @Volatile private var udpSocket: DatagramSocket? = null
    private var udpThread: Thread? = null
    private var mcLock: WifiManager.MulticastLock? = null
    private var netCallback: ConnectivityManager.NetworkCallback? = null

    private val retry = Runnable { if (ws == null) connectNext() }

    // ── lifecycle ────────────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = LinkPrefs(this)
        thread = HandlerThread("al-link").also { it.start() }
        handler = Handler(thread.looper)
        files = FileTransfer(this)
        startAsForeground()
        instance = this
        synchronized(pending) {
            queue.addAll(pending); pending.clear()
        }
        registerNetworkCallback()
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        smsObserver = PhoneData.SmsObserver(this, handler, prefs) { send("sms", it) }.also {
            it.register()
            handler.post { it.onChange(false, null) } // catch up on SMS received while we were dead
        }
        mmsObserver = Mms.Observer(this, handler) { send("sms", it) }.also { it.register() }
        handler.post { connectNext() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!prefs.isPaired) { stopSelf(); return START_NOT_STICKY }
        if (intent?.action == ACTION_RECONNECT) handler.post {
            ws?.cancel(); ws = null; authed = false; attempt = 0
            handler.removeCallbacks(retry)
            stopDiscovery() // macId may have changed after re-pairing
            connectNext()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        try { unregisterReceiver(batteryReceiver) } catch (_: Exception) {}
        try { smsObserver?.unregister() } catch (_: Exception) {}
        try { mmsObserver?.unregister() } catch (_: Exception) {}
        files.shutdown()
        io.shutdownNow()
        netCallback?.let {
            try { (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it) } catch (_: Exception) {}
        }
        handler.post {
            ws?.close(1000, "bye"); ws = null
            stopDiscovery()
            setStatus(if (prefs.isPaired) "searching" else "unpaired")
            thread.quitSafely()
        }
        super.onDestroy()
    }

    private fun startAsForeground() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Связь с Mac", NotificationManager.IMPORTANCE_MIN)
            )
        }
        val n = buildNotification("Поиск Mac…")
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun buildNotification(text: String): Notification {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val clip = PendingIntent.getActivity(
            this, 2,
            Intent(this, ClipPushActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        @Suppress("DEPRECATION")
        return b.setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("AndroidLink")
            .setContentText(text)
            .setContentIntent(pi)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Буфер → Mac", clip).build())
            .build()
    }

    private fun setStatus(s: String) {
        if (status == s) return
        status = s
        val text = when (s) {
            "connected" -> "Подключено к ${prefs.macName ?: "Mac"}"
            "connecting" -> "Подключение…"
            "unauthorized" -> "Mac не узнал телефон — отсканируй QR заново"
            else -> "Поиск Mac…"
        }
        try {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIF_ID, buildNotification(text))
        } catch (_: Exception) {}
        emitUi("status", s)
    }

    fun emitUi(kind: String, data: Any) {
        if (listeners.isEmpty()) return
        main.post { listeners.forEach { it(kind, data) } }
    }

    // ── connection ───────────────────────────────────────────────────────

    private fun connectNext() {
        if (ws != null) return
        val hosts = prefs.hosts
        startDiscovery()
        if (hosts.isEmpty()) { setStatus("searching"); return }
        connect(hosts[attempt % hosts.size], prefs.port)
    }

    private fun connect(ip: String, port: Int) {
        val key = prefs.key ?: run { setStatus("unpaired"); return }
        if (ws != null) return
        setStatus("connecting")
        lastHost = "$ip:$port"
        setDiag("Подключаюсь к $ip:$port…")
        phoneSid = LinkCrypto.randomId()
        authed = false
        wsHost = ip
        val req = Request.Builder().url("ws://$ip:$port").build()
        lateinit var sock: WebSocket
        sock = http.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                handler.post { if (webSocket === ws) sendHello(webSocket) }
            }
            override fun onMessage(webSocket: WebSocket, text: String) {
                handler.post { if (webSocket === ws) onFrame(key, text, ip, port) }
            }
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(1000, null)
                handler.post { onDrop(webSocket, code) }
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                handler.post {
                    if (webSocket === ws) setDiag("Mac закрыл соединение ($code ${reason.ifEmpty { "" }})".trim())
                    onDrop(webSocket, code)
                }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                handler.post {
                    if (webSocket === ws) setDiag("$ip:$port — ${t.javaClass.simpleName}: ${t.message ?: ""}" +
                        (response?.let { " (HTTP ${it.code})" } ?: ""))
                    onDrop(webSocket, -1)
                }
            }
        })
        ws = sock
        handler.postDelayed({
            if (ws === sock && !authed) { setDiag("$ip:$port — нет ответа 10 с"); sock.cancel() }
        }, 10_000)
    }

    private fun sendHello(sock: WebSocket) {
        val hello = JSONObject()
            .put("hello", 2)
            .put("device", prefs.deviceId)
            .put("name", deviceName())
            .put("s", phoneSid)
        prefs.pairId?.let { hello.put("pair", it) }
        sock.send(hello.toString())
    }

    private fun onFrame(key: ByteArray, frame: String, ip: String, port: Int) {
        val plain = LinkCrypto.open(key, frame) ?: run {
            setDiag("Не удалось расшифровать ответ Mac — отсканируй QR заново"); ws?.cancel(); return
        }
        val env = try { JSONObject(plain) } catch (e: Exception) { return }
        if (env.optString("s") != phoneSid) return
        val type = env.optString("type")
        val payload = env.optJSONObject("payload") ?: JSONObject()

        if (!authed) {
            if (type != "welcome") return
            authed = true
            attempt = 0
            macSid = payload.optString("s")
            payload.optString("name").takeIf { it.isNotEmpty() }?.let { prefs.setMacName(it) }
            prefs.clearPairId()
            prefs.rememberHost(ip, port)
            handler.removeCallbacks(retry)
            stopDiscovery()
            setStatus("connected")
            setDiag("")
            sendNow("device_info", deviceInfo())
            while (queue.isNotEmpty() && ws != null) {
                val (t, p) = queue.removeFirst(); sendNow(t, p)
            }
            return
        }
        handleCommand(type, payload, env.optString("id"))
        if (!type.startsWith("file_")) emitUi("message", env.toString())
    }

    private fun onDrop(sock: WebSocket, code: Int) {
        if (sock !== ws) return
        ws = null
        authed = false
        if (code == 4401 || code == 4403) {
            setStatus("unauthorized")
        } else {
            setStatus("searching")
        }
        startDiscovery()
        val delay = (1000L shl attempt.coerceAtMost(5)).coerceAtMost(30_000L)
        attempt++
        handler.removeCallbacks(retry)
        handler.postDelayed(retry, delay)
    }

    fun send(type: String, payload: JSONObject) = handler.post {
        if (authed && ws != null) sendNow(type, payload)
        // battery goes in device_info on connect; file chunks are never buffered
        else if (type != "battery" && !type.startsWith("file_")) {
            queue.addLast(type to payload)
            while (queue.size > MAX_QUEUE) queue.removeFirst()
        }
    }

    private fun sendNow(type: String, payload: JSONObject) {
        val key = prefs.key ?: return
        val env = JSONObject()
            .put("type", type)
            .put("payload", payload)
            .put("id", UUID.randomUUID().toString())
            .put("s", macSid)
        ws?.send(LinkCrypto.seal(key, env.toString()))
    }

    // ── commands from the Mac ────────────────────────────────────────────

    private fun handleCommand(type: String, p: JSONObject, msgId: String) {
        if (files.onMessage(type, p)) return
        val reply: (String, JSONObject) -> Unit = { t, o -> send(t, o) }
        when (type) {
            "sms_sync" -> io.execute { PhoneData.syncSms(this, p.optInt("limit", 1500).coerceIn(1, 5000), reply) }
            "calls_sync" -> io.execute { PhoneData.syncCalls(this, p.optInt("limit", 300).coerceIn(1, 2000), reply) }
            "contacts_sync" -> io.execute { PhoneData.syncContacts(this, reply) }
            "call_action" -> {
                val ok = PhoneControl.callAction(this, p.optString("action"))
                sendNow("call_action_result", JSONObject().put("action", p.optString("action")).put("ok", ok))
            }
            "call_dial" -> {
                val ok = PhoneControl.dial(this, p.optString("number"))
                sendNow("call_action_result", JSONObject().put("action", "dial").put("ok", ok))
            }
            "ring" -> PhoneControl.ring(this, p.optInt("seconds", 30))
            "ring_stop" -> PhoneControl.stopRing(this)
            "notification_dismiss" -> AndroidLinkNotificationService.dismiss(p.optString("key"))
            "notification_reply" -> {
                val ok = AndroidLinkNotificationService.reply(p.optString("key"), p.optString("text"))
                sendNow("notification_reply_result", JSONObject().put("key", p.optString("key")).put("ok", ok))
            }
            "sms_reply" -> {
                val to = p.optString("address").ifEmpty { p.optString("to") }
                val body = p.optString("body")
                val ok = sendSms(to, body)
                sendNow("sms_status", JSONObject()
                    .put("ref", p.optString("id").ifEmpty { msgId })
                    .put("address", to)
                    .put("status", if (ok) "sent" else "failed"))
            }
            "clipboard" -> {
                val text = p.optString("text")
                if (text.isNotEmpty()) main.post {
                    val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("AndroidLink", text))
                }
            }
            "clip_image" -> {
                val bytes = try { android.util.Base64.decode(p.optString("image"), android.util.Base64.DEFAULT) } catch (e: Exception) { null }
                if (bytes != null && bytes.isNotEmpty()) {
                    val uri = ClipProvider.store(this, bytes)
                    main.post {
                        val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                        cm.setPrimaryClip(ClipData.newUri(contentResolver, "AndroidLink", uri))
                    }
                }
            }
        }
    }

    private fun sendSms(to: String, body: String): Boolean {
        if (to.isBlank() || body.isBlank()) return false
        return try {
            @Suppress("DEPRECATION")
            val sm = if (Build.VERSION.SDK_INT >= 31) getSystemService(SmsManager::class.java) else SmsManager.getDefault()
            val parts = sm.divideMessage(body)
            // Group thread: Mac sends "a,b,c" — deliver to every participant.
            for (r in to.split(',').map { it.trim() }.filter { it.isNotEmpty() }) {
                if (parts.size > 1) sm.sendMultipartTextMessage(r, null, parts, null, null)
                else sm.sendTextMessage(r, null, body, null, null)
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "sendSms failed: ${e.message}")
            false
        }
    }

    // ── discovery (UDP beacon "ANDROIDLINK2|<macId>|<port>") ────────────

    private fun startDiscovery() {
        if (udpThread != null) return
        try {
            val wm = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            mcLock = wm.createMulticastLock("androidlink").apply { setReferenceCounted(false); acquire() }
        } catch (_: Exception) {}
        val macId = prefs.macId
        udpThread = Thread({
            try {
                val sock = DatagramSocket(null).apply {
                    reuseAddress = true
                    broadcast = true
                    bind(InetSocketAddress(UDP_PORT))
                }
                udpSocket = sock
                val buf = ByteArray(512)
                while (!Thread.currentThread().isInterrupted) {
                    val pkt = DatagramPacket(buf, buf.size)
                    sock.receive(pkt)
                    val parts = String(pkt.data, 0, pkt.length, Charsets.UTF_8).split('|')
                    if (parts.size >= 3 && parts[0] == "ANDROIDLINK2" && parts[1] == macId) {
                        val ip = pkt.address.hostAddress ?: continue
                        val port = parts[2].toIntOrNull() ?: continue
                        handler.post { onBeacon(ip, port) }
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "udp stopped: ${e.message}")
            } finally {
                udpSocket?.close()
                handler.post { if (udpThread === Thread.currentThread()) udpThread = null }
            }
        }, "al-udp").also { it.isDaemon = true; it.start() }
    }

    private fun stopDiscovery() {
        udpThread?.interrupt()
        udpThread = null
        udpSocket?.close()
        udpSocket = null
        try { mcLock?.release() } catch (_: Exception) {}
        mcLock = null
    }

    private fun setDiag(d: String) {
        diag = d
        Log.i(TAG, d)
        emitUi("diag", d)
    }

    private fun onBeacon(ip: String, port: Int) {
        lastBeacon = System.currentTimeMillis()
        if (authed) return
        if (ws != null && wsHost == ip) return
        ws?.cancel(); ws = null
        handler.removeCallbacks(retry)
        connect(ip, port)
    }

    private fun registerNetworkCallback() {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                handler.post {
                    if (!authed) { ws?.cancel(); ws = null; attempt = 0; handler.removeCallbacks(retry); connectNext() }
                }
            }
        }
        try { cm.registerDefaultNetworkCallback(cb); netCallback = cb } catch (_: Exception) {}
    }

    // ── device info / battery ────────────────────────────────────────────

    private fun deviceName(): String {
        val m = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        return if (Build.MODEL.startsWith(m, ignoreCase = true)) Build.MODEL else "$m ${Build.MODEL}"
    }

    private fun deviceInfo(): JSONObject = JSONObject()
        .put("name", deviceName())
        .put("model", Build.MODEL)
        .put("android", Build.VERSION.RELEASE)
        .put("battery", lastBattery)
        .put("charging", lastCharging)

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            val pct = if (level >= 0 && scale > 0) level * 100 / scale else -1
            val st = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val charging = st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL
            if (pct == lastBattery && charging == lastCharging) return
            lastBattery = pct; lastCharging = charging
            send("battery", JSONObject().put("level", pct).put("charging", charging))
        }
    }
}
