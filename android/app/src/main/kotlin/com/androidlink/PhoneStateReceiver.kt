package com.androidlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PhoneStateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Handled via CallStreamHandler EventChannel when app is in foreground
    }
}
