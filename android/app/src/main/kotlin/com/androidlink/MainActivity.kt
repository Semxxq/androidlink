package com.androidlink

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Thin UI bridge. The link itself lives in [LinkService];
 * Flutter only pairs, shows status and sends user actions.
 */
class MainActivity : FlutterActivity() {

    private var uiListener: ((String, Any) -> Unit)? = null

    override fun onResume() {
        super.onResume()
        PhoneControl.stopRing(this) // "find my phone" stops once you have it
        LinkService.start(this)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val messenger = engine.dartExecutor.binaryMessenger
        val prefs = LinkPrefs(this)

        EventChannel(messenger, "com.androidlink/link").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val l: (String, Any) -> Unit = { kind, data ->
                    events.success(mapOf("kind" to kind, "data" to data))
                }
                uiListener = l
                LinkService.listeners.add(l)
                events.success(mapOf("kind" to "status", "data" to currentStatus(prefs)))
            }
            override fun onCancel(arguments: Any?) {
                uiListener?.let { LinkService.listeners.remove(it) }
                uiListener = null
            }
        })

        MethodChannel(messenger, "com.androidlink/methods").setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> result.success(mapOf(
                    "status" to currentStatus(prefs),
                    "paired" to prefs.isPaired,
                    "macName" to prefs.macName,
                ))
                "pair" -> {
                    val ok = prefs.pair(call.argument<String>("qr") ?: "")
                    if (ok) LinkService.start(this, LinkService.ACTION_RECONNECT)
                    result.success(ok)
                }
                "unpair" -> {
                    LinkService.stop(this)
                    prefs.clear()
                    result.success(true)
                }
                "connectIp" -> {
                    val ip = call.argument<String>("ip")?.trim() ?: ""
                    if (ip.isNotEmpty() && prefs.isPaired) {
                        prefs.rememberHost(ip)
                        LinkService.start(this, LinkService.ACTION_RECONNECT)
                        result.success(true)
                    } else result.success(false)
                }
                "send" -> {
                    val type = call.argument<String>("type") ?: ""
                    val payload = try { JSONObject(call.argument<String>("payload") ?: "{}") } catch (e: Exception) { JSONObject() }
                    if (type.isNotEmpty()) LinkService.post(this, type, payload)
                    result.success(null)
                }
                "sendFiles" -> {
                    val svc = LinkService.instance
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    if (svc == null || LinkService.status != "connected") result.success(false)
                    else {
                        paths.forEach { svc.files.send(Uri.fromFile(java.io.File(it))) }
                        result.success(true)
                    }
                }
                "systemAccent" -> result.success(
                    if (Build.VERSION.SDK_INT >= 31) getColor(android.R.color.system_accent1_500) else null
                )
                "isBatteryExempt" -> result.success(isBatteryExempt())
                "requestBatteryExemption" -> {
                    requestBatteryExemption()
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "openAppSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "isNotificationListenerEnabled" -> {
                    val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
                    result.success(flat.contains(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        uiListener?.let { LinkService.listeners.remove(it) }
        uiListener = null
        super.onDestroy()
    }

    private fun currentStatus(prefs: LinkPrefs): String =
        if (!prefs.isPaired) "unpaired"
        else if (LinkService.instance == null) "searching"
        else LinkService.status

    private fun isBatteryExempt(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption() {
        if (Build.VERSION.SDK_INT < 23 || isBatteryExempt()) return
        try {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }
}
