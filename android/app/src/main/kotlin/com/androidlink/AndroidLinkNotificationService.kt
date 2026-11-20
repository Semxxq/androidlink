package com.androidlink

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject

/**
 * Mirrors phone notifications to the Mac, syncs dismissal both ways and
 * lets the Mac reply to messenger notifications (Telegram, WhatsApp…)
 * through their inline-reply action.
 */
class AndroidLinkNotificationService : NotificationListenerService() {

    companion object {
        @Volatile var instance: AndroidLinkNotificationService? = null
            private set

        fun dismiss(key: String) {
            try { instance?.cancelNotification(key) } catch (_: Exception) {}
        }

        fun reply(key: String, text: String): Boolean {
            val svc = instance ?: return false
            val sbn = try { svc.activeNotifications?.firstOrNull { it.key == key } } catch (_: Exception) { null } ?: return false
            val action = replyAction(sbn.notification) ?: return false
            val inputs = action.remoteInputs ?: return false
            val intent = Intent().addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            val results = Bundle()
            inputs.forEach { results.putCharSequence(it.resultKey, text) }
            RemoteInput.addResultsToIntent(inputs, intent, results)
            return try { action.actionIntent.send(svc, 0, intent); true } catch (e: Exception) {
                Log.w("NotifService", "reply failed: ${e.message}"); false
            }
        }

        private fun replyAction(n: Notification): Notification.Action? =
            n.actions?.firstOrNull { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true }
    }

    override fun onListenerConnected() { instance = this }
    override fun onListenerDisconnected() { if (instance === this) instance = null }
    override fun onDestroy() { if (instance === this) instance = null; super.onDestroy() }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (!shouldMirror(sbn)) return
        val n = sbn.notification
        val ex = n.extras
        val title = (ex.getCharSequence(Notification.EXTRA_TITLE)
            ?: ex.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE))?.toString() ?: ""
        val body = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        if (title.isEmpty() && body.isEmpty()) return

        LinkService.post(this, "notification", JSONObject()
            .put("key", sbn.key)
            .put("app", appLabel(sbn.packageName))
            .put("pkg", sbn.packageName)
            .put("title", title)
            .put("body", body)
            .put("ts", sbn.postTime)
            .put("canReply", replyAction(n) != null))
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
        // SMS already sync natively — avoid duplicates from the SMS app.
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
