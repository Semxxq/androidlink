package com.androidlink

import android.content.Intent
import android.provider.Settings
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        val messenger = engine.dartExecutor.binaryMessenger

        // SMS stream → Flutter
        EventChannel(messenger, "com.androidlink/sms")
            .setStreamHandler(SmsStreamHandler(this))

        // Calls stream → Flutter
        EventChannel(messenger, "com.androidlink/calls")
            .setStreamHandler(CallStreamHandler(this))

        // Notifications stream → Flutter
        EventChannel(messenger, "com.androidlink/notifications")
            .setStreamHandler(NotificationStreamHandler())

        // Method channel: SMS reply, settings, clipboard
        MethodChannel(messenger, "com.androidlink/methods").setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val to   = call.argument<String>("to")   ?: ""
                    val body = call.argument<String>("body") ?: ""
                    try {
                        @Suppress("DEPRECATION")
                        val sm = SmsManager.getDefault()
                        sm.sendTextMessage(to, null, body, null, null)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SMS_ERROR", e.message, null)
                    }
                }
                "openNotificationSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "isNotificationListenerEnabled" -> {
                    val flat = Settings.Secure.getString(
                        contentResolver, "enabled_notification_listeners"
                    ) ?: ""
                    result.success(flat.contains(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }
}
