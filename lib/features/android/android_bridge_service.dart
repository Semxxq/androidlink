import 'dart:async';
import 'package:flutter/services.dart';

import '../bridge/services/bridge_service.dart';
import '../../core/constants/app_constants.dart';

/// Запускается только на Android.
/// Слушает нативные EventChannel'ы (SMS, звонки, уведомления)
/// и пересылает всё через BridgeService на Mac.
/// Также принимает команды с Мака (ответ на SMS, буфер обмена).
class AndroidBridgeService {
  AndroidBridgeService._();
  static final AndroidBridgeService instance = AndroidBridgeService._();

  static const _smsChannel   = EventChannel('com.androidlink/sms');
  static const _callChannel  = EventChannel('com.androidlink/calls');
  static const _notifChannel = EventChannel('com.androidlink/notifications');
  static const _methods      = MethodChannel('com.androidlink/methods');

  final List<StreamSubscription> _subs = [];

  void start() {
    // SMS → Mac
    _subs.add(_smsChannel.receiveBroadcastStream().listen((data) {
      if (data is! Map) return;
      BridgeService.instance.sendRaw(
          Map<String, dynamic>.from(data), AL.typeSms);
    }));

    // Звонки → Mac
    _subs.add(_callChannel.receiveBroadcastStream().listen((data) {
      if (data is! Map) return;
      BridgeService.instance.sendRaw(
          Map<String, dynamic>.from(data), AL.typeCall);
    }));

    // Уведомления → Mac
    _subs.add(_notifChannel.receiveBroadcastStream().listen((data) {
      if (data is! Map) return;
      BridgeService.instance.sendRaw(
          Map<String, dynamic>.from(data), AL.typeNotif);
    }));

    // Входящие сообщения с Мака
    _subs.add(BridgeService.instance.messages.listen(_handleFromMac));
  }

  void _handleFromMac(BridgeMessage msg) {
    switch (msg.type) {
      case AL.typeSmsReply:
        _sendSms(
          to:   msg.payload['to']   as String? ?? '',
          body: msg.payload['body'] as String? ?? '',
        );
      case AL.typeClipboard:
        final text = msg.payload['text'] as String? ?? '';
        if (text.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: text));
        }
    }
  }

  Future<void> _sendSms({required String to, required String body}) async {
    if (to.isEmpty || body.isEmpty) return;
    try {
      await _methods.invokeMethod('sendSms', {'to': to, 'body': body});
    } catch (_) {}
  }

  /// Отправить текущий буфер обмена Android → Mac
  Future<void> pushClipboardToMac() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    BridgeService.instance.sendRaw({'text': data.text!}, AL.typeClipboard);
  }

  /// Открыть настройки разрешения для Notification Listener
  Future<void> openNotificationSettings() async {
    try {
      await _methods.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  /// Проверить, выдано ли разрешение Notification Listener
  Future<bool> isNotificationListenerEnabled() async {
    try {
      return await _methods.invokeMethod<bool>('isNotificationListenerEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  void stop() {
    for (final sub in _subs) sub.cancel();
    _subs.clear();
  }
}
