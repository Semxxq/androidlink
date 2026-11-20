package com.androidlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONObject
import java.util.UUID

/** Incoming SMS → Mac. Manifest-registered, works with the app closed. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        // Multipart SMS arrive as several PDUs — glue them per sender.
        val bodies = LinkedHashMap<String, StringBuilder>()
        var ts = System.currentTimeMillis()
        for (m in parts) {
            val addr = m.displayOriginatingAddress ?: m.originatingAddress ?: continue
            bodies.getOrPut(addr) { StringBuilder() }.append(m.displayMessageBody ?: "")
            ts = m.timestampMillis
        }
        for ((addr, body) in bodies) {
            val p = JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("address", addr)
                .put("body", body.toString())
                .put("ts", ts)
                .put("in", true)
                .put("read", false)
            Contacts.name(context, addr)?.let { p.put("name", it) }
            LinkService.post(context, "sms", p)
        }
    }
}
