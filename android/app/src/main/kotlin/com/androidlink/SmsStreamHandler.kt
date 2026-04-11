package com.androidlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.provider.Telephony
import io.flutter.plugin.common.EventChannel

class SmsStreamHandler(private val context: Context) : EventChannel.StreamHandler {

    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

                val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                val grouped  = mutableMapOf<String, StringBuilder>()

                for (msg in messages) {
                    val sender = msg.originatingAddress ?: "Unknown"
                    grouped.getOrPut(sender) { StringBuilder() }.append(msg.messageBody)
                }

                for ((sender, body) in grouped) {
                    events.success(mapOf(
                        "address"   to sender,
                        "body"      to body.toString(),
                        "ts"        to System.currentTimeMillis(),
                        "in"        to true,
                        "id"        to System.currentTimeMillis().toString(),
                        "read"      to false,
                        "status"    to "delivered",
                    ))
                }
            }
        }

        context.registerReceiver(
            receiver,
            IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION),
        )
    }

    override fun onCancel(arguments: Any?) {
        context.unregisterReceiver(receiver)
        receiver = null
    }
}
