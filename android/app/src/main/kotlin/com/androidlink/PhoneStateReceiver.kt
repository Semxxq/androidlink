package com.androidlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import org.json.JSONObject
import java.util.UUID

/**
 * Call state → Mac. One call keeps one id through
 * ringing → answered → ended, so the Mac can update the same entry.
 * type: incoming | outgoing | missed.
 */
class PhoneStateReceiver : BroadcastReceiver() {

    companion object {
        private var last = TelephonyManager.EXTRA_STATE_IDLE
        private var callId = ""
        private var number: String? = null
        private var incoming = false
        private var answered = false
        private var start = 0L
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        @Suppress("DEPRECATION")
        val num = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        // Android 10+ delivers each state twice (with and without the number).
        if (state == last) {
            if (num != null && number == null) {
                number = num
                if (state == TelephonyManager.EXTRA_STATE_RINGING) emit(context, "ringing", true)
            }
            return
        }
        val prev = last
        last = state
        if (num != null) number = num

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                callId = UUID.randomUUID().toString()
                incoming = true; answered = false
                start = System.currentTimeMillis()
                emit(context, "ringing", true)
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                if (prev == TelephonyManager.EXTRA_STATE_RINGING) {
                    answered = true
                    start = System.currentTimeMillis()
                    emit(context, "answered", true)
                } else {
                    callId = UUID.randomUUID().toString()
                    incoming = false; answered = true
                    start = System.currentTimeMillis()
                    emit(context, "dialing", true)
                }
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                if (callId.isEmpty()) return
                emit(context, "ended", false)
                callId = ""; number = null
            }
        }
    }

    private fun emit(ctx: Context, state: String, active: Boolean) {
        val type = when {
            !incoming -> "outgoing"
            !active && !answered -> "missed"
            else -> "incoming"
        }
        val now = System.currentTimeMillis()
        val p = JSONObject()
            .put("id", callId)
            .put("address", number ?: "Неизвестный")
            .put("type", type)
            .put("state", state)
            .put("ts", start)
            .put("dur", if (!active && answered) (now - start) / 1000 else 0)
            .put("active", active)
        number?.let { n -> Contacts.name(ctx, n)?.let { p.put("name", it) } }
        LinkService.post(ctx, "call", p)
    }
}
