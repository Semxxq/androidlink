package com.androidlink

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // SMS EventChannel → Flutter stream
        EventChannel(engine.dartExecutor.binaryMessenger, "com.androidlink/sms")
            .setStreamHandler(SmsStreamHandler(this))

        // Phone state EventChannel → Flutter stream
        EventChannel(engine.dartExecutor.binaryMessenger, "com.androidlink/calls")
            .setStreamHandler(CallStreamHandler(this))
    }
}
