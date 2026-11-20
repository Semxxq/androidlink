package com.androidlink

import android.app.Notification
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

/** Mirrors phone notifications to the Mac (and their dismissal). */
class AndroidLinkNotificationService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (!shouldMirror(sbn)) return
        val n = sbn.notification
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val body = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        if (title.isEmpty() && body.isEmpty()) return

        LinkService.post(this, "notification", JSONObject()
            .put("key", sbn.key)
            .put("app", appLabel(sbn.packageName))
            .put("pkg", sbn.packageName)
            .put("title", title)
            .put("body", body)
            .put("ts", sbn.postTime))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        if (!shouldMirror(sbn)) return
        LinkService.post(this, "notification_removed", JSONObject().put("key", sbn.key))
    }

    private fun shouldMirror(sbn: StatusBarNotification): Boolean {
        if (sbn.packageName == packageName) return false
        if (sbn.isOngoing) return false
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return false
        // SMS already arrive via SmsReceiver — avoid duplicates from the SMS app.
        if (sbn.packageName == Telephony.Sms.getDefaultSmsPackage(this)) return false
        return true
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }
}
