package com.androidlink

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.util.Log

/** Actions the Mac can trigger on the phone: calls and "find my phone". */
object PhoneControl {
    private const val TAG = "PhoneControl"
    private val main = Handler(Looper.getMainLooper())

    @SuppressLint("MissingPermission")
    fun callAction(ctx: Context, action: String): Boolean = try {
        val tm = ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        when (action) {
            "answer" -> if (Build.VERSION.SDK_INT >= 26) { tm.acceptRingingCall(); true } else false
            "decline", "end" -> if (Build.VERSION.SDK_INT >= 28) {
                @Suppress("DEPRECATION") tm.endCall()
            } else false
            else -> false
        }
    } catch (e: Exception) {
        Log.w(TAG, "callAction $action: ${e.message}"); false
    }

    @SuppressLint("MissingPermission")
    fun dial(ctx: Context, number: String): Boolean = try {
        val tm = ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        tm.placeCall(Uri.fromParts("tel", number, null), null)
        true
    } catch (e: Exception) {
        Log.w(TAG, "dial: ${e.message}"); false
    }

    // ── Find my phone ────────────────────────────────────────────────────

    private var ringtone: Ringtone? = null
    private var appCtx: Context? = null
    private var savedVolume = -1
    private val stopper = Runnable { stopRing(null) }

    private var vibrator: android.os.Vibrator? = null
    private const val RING_CH = "find_phone"
    private const val RING_ID = 4711

    fun ring(ctx: Context, seconds: Int = 30): Boolean = main.post {
        if (ringtone?.isPlaying == true) return@post
        appCtx = ctx.applicationContext
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
        try {
            am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        } catch (e: Exception) { Log.w("AndroidLink", "ring volume: ${e.message}") }
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        // Default alarm may be unset ("None") on some phones — walk fallbacks.
        val candidates = listOfNotNull(
            RingtoneManager.getActualDefaultRingtoneUri(ctx, RingtoneManager.TYPE_ALARM),
            RingtoneManager.getActualDefaultRingtoneUri(ctx, RingtoneManager.TYPE_RINGTONE),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            android.provider.Settings.System.DEFAULT_RINGTONE_URI,
        )
        for (uri in candidates) {
            val r = try { RingtoneManager.getRingtone(ctx, uri) } catch (_: Exception) { null } ?: continue
            r.audioAttributes = attrs
            if (Build.VERSION.SDK_INT >= 28) r.isLooping = true
            try { r.play() } catch (_: Exception) { continue }
            ringtone = r
            break
        }
        // Vibrate too: works even when sound is impossible.
        try {
            @Suppress("DEPRECATION")
            val v = if (Build.VERSION.SDK_INT >= 31)
                (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager).defaultVibrator
            else ctx.getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
            v.vibrate(android.os.VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0), attrs)
            vibrator = v
        } catch (e: Exception) { Log.w("AndroidLink", "vibrate: ${e.message}") }
        showRingNotification(ctx)
        main.removeCallbacks(stopper)
        main.postDelayed(stopper, seconds * 1000L)
    }

    private fun showRingNotification(ctx: Context) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(RING_CH) == null) {
                nm.createNotificationChannel(android.app.NotificationChannel(RING_CH, "Поиск телефона",
                    android.app.NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null); enableVibration(false) })
            }
            // Opening the app stops the ring (MainActivity.onResume).
            val open = android.app.PendingIntent.getActivity(ctx, 0,
                android.content.Intent(ctx, MainActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK),
                android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT)
            @Suppress("DEPRECATION")
            val b = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(ctx, RING_CH) else android.app.Notification.Builder(ctx)
            val n = b.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("Mac ищет этот телефон")
                .setContentText("Нажми, чтобы остановить звук")
                .setCategory(android.app.Notification.CATEGORY_ALARM)
                .setContentIntent(open)
                .setFullScreenIntent(open, true)
                .addAction(android.app.Notification.Action.Builder(null, "Нашёл", open).build())
                .setAutoCancel(true)
                .build()
            nm.notify(RING_ID, n)
        } catch (e: Exception) { Log.w("AndroidLink", "ring notif: ${e.message}") }
    }

    fun stopRing(ctx: Context?): Boolean = main.post {
        main.removeCallbacks(stopper)
        ringtone?.stop()
        ringtone = null
        try { vibrator?.cancel() } catch (_: Exception) {}
        vibrator = null
        val c = ctx ?: appCtx
        try {
            (c?.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager)?.cancel(RING_ID)
        } catch (_: Exception) {}
        if (c != null && savedVolume >= 0) {
            try {
                (c.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
                    .setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
            } catch (_: Exception) {}
            savedVolume = -1
        }
    }

    val isRinging: Boolean get() = ringtone?.isPlaying == true
}
