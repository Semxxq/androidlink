import 'package:flutter/services.dart';

import '../bridge/services/bridge_service.dart';
import '../../core/constants/app_constants.dart';

/// Android-only helpers for the UI. SMS / calls / notifications are
/// forwarded natively by LinkService, even with the app closed.
class AndroidBridgeService {
  AndroidBridgeService._();
  static final AndroidBridgeService instance = AndroidBridgeService._();

  static const _methods = MethodChannel('com.androidlink/methods');

  /// Send current Android clipboard → Mac.
  Future<void> pushClipboardToMac() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    BridgeService.instance.sendRaw({'text': text}, AL.typeClipboard);
  }

  Future<void> openNotificationSettings() => _call('openNotificationSettings');
  Future<void> openAppSettings() => _call('openAppSettings');
  Future<void> requestBatteryExemption() => _call('requestBatteryExemption');

  Future<bool> isNotificationListenerEnabled() => _bool('isNotificationListenerEnabled');
  Future<bool> isBatteryExempt() => _bool('isBatteryExempt');

  Future<void> _call(String m) async {
    try {
      await _methods.invokeMethod(m);
    } catch (_) {}
  }

  Future<bool> _bool(String m) async {
    try {
      return await _methods.invokeMethod<bool>(m) ?? false;
    } catch (_) {
      return false;
    }
  }
}
