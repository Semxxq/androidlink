package com.androidlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Handled via SmsStreamHandler EventChannel when app is in foreground
        // This receiver exists to satisfy the manifest declaration
    }
}
