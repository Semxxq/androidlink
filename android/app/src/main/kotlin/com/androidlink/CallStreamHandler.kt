package com.androidlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.telephony.TelephonyManager
import io.flutter.plugin.common.EventChannel
import java.util.UUID

class CallStreamHandler(private val context: Context) : EventChannel.StreamHandler {

    private var receiver: BroadcastReceiver? = null
    private var callStartTime: Long = 0

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
                val number   = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                    ?: intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
                    ?: "Unknown"

                when (stateStr) {
                    TelephonyManager.EXTRA_STATE_RINGING -> {
                        callStartTime = System.currentTimeMillis()
                        events.success(mapOf(
                            "id"      to UUID.randomUUID().toString(),
                            "address" to number,
                            "type"    to "incoming",
                            "ts"      to callStartTime,
                            "active"  to true,
                        ))
                    }
                    TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                        // Звонок принят — не делаем ничего доп.
                    }
                    TelephonyManager.EXTRA_STATE_IDLE -> {
                        val dur = if (callStartTime > 0)
                            (System.currentTimeMillis() - callStartTime) / 1000
                        else 0L
                        callStartTime = 0
                        events.success(mapOf(
                            "id"      to UUID.randomUUID().toString(),
                            "address" to number,
                            "type"    to "incoming",
                            "ts"      to System.currentTimeMillis(),
                            "dur"     to dur,
                            "active"  to false,
                        ))
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            addAction(Intent.ACTION_NEW_OUTGOING_CALL)
        }
        context.registerReceiver(receiver, filter)
    }

    override fun onCancel(arguments: Any?) {
        context.unregisterReceiver(receiver)
        receiver = null
    }
}
