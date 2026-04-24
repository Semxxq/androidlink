package com.androidlink

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class AndroidLinkNotificationService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (sbn.packageName == packageName) return   // игнорируем свои уведомления
        NotificationStreamHandler.postNotification(sbn)
    }
}
