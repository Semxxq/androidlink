package com.androidlink

import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel

class NotificationStreamHandler : EventChannel.StreamHandler {
    companion object {
        var sink: EventChannel.EventSink? = null

        fun postNotification(sbn: StatusBarNotification) {
            val extras = sbn.notification.extras
            val title  = extras.getCharSequence("android.title")?.toString() ?: ""
            val body   = extras.getCharSequence("android.text")?.toString()  ?: ""
            if (title.isEmpty() && body.isEmpty()) return

            val payload = mapOf(
                "app"   to sbn.packageName,
                "title" to title,
                "body"  to body,
                "ts"    to sbn.postTime
            )
            sink?.success(payload)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}
