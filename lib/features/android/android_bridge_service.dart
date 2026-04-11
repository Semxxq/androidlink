import 'dart:async';
import 'package:flutter/services.dart';

import '../bridge/services/bridge_service.dart';
import '../../core/constants/app_constants.dart';

/// Запускается только на Android.
/// Слушает нативные EventChannel'ы (SMS, звонки)
/// и пересылает всё через BridgeService на Mac.
class AndroidBridgeService {
  AndroidBridgeService._();
  static final AndroidBridgeService instance = AndroidBridgeService._();

  static const _smsChannel  = EventChannel('com.androidlink/sms');
  static const _callChannel = EventChannel('com.androidlink/calls');

  StreamSubscription? _smsSub;
  StreamSubscription? _callSub;

  void start() {
    // SMS
    _smsSub = _smsChannel.receiveBroadcastStream().listen((data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      BridgeService.instance.sendRaw(payload, AL.typeSms);
    });

    // Звонки
    _callSub = _callChannel.receiveBroadcastStream().listen((data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      BridgeService.instance.sendRaw(payload, AL.typeCall);
    });
  }

  void stop() {
    _smsSub?.cancel();
    _callSub?.cancel();
  }
}
