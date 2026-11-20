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

    fun ring(ctx: Context, seconds: Int = 30): Boolean = main.post {
        if (ringtone?.isPlaying == true) return@post
        appCtx = ctx.applicationContext
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
        try {
            am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        } catch (_: Exception) {}
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        ringtone = RingtoneManager.getRingtone(ctx, uri)?.apply {
            audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= 28) isLooping = true
            play()
        }
        main.removeCallbacks(stopper)
        main.postDelayed(stopper, seconds * 1000L)
    }

    fun stopRing(ctx: Context?): Boolean = main.post {
        main.removeCallbacks(stopper)
        ringtone?.stop()
        ringtone = null
        val c = ctx ?: appCtx
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
