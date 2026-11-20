package com.androidlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * SMS themselves are picked up from the SMS provider by PhoneData.SmsObserver
 * (covers sent messages too, no duplicates). This receiver only makes sure the
 * link service is running when a message arrives.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        LinkService.start(context)
    }
}
