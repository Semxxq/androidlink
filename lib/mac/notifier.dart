import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Native macOS banners with inline actions (reply / answer / decline).
///
/// Payload format: "<kind>|<id>" — kind = sms | call | notif | file.
class MacNotifier {
  MacNotifier._();
  static final MacNotifier instance = MacNotifier._();

  static const catSms = 'sms';
  static const catCall = 'call';
  static const catReply = 'notif_reply';
  static const catFile = 'file';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool enabled = true;
  void Function(String kind, String id, String? action, String? input)? onResponse;

  Future<void> init() async {
    final settings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        notificationCategories: [
          DarwinNotificationCategory(catSms, actions: [
            DarwinNotificationAction.text('reply', 'Ответить',
                buttonTitle: 'Отправить', placeholder: 'Сообщение'),
          ]),
          DarwinNotificationCategory(catReply, actions: [
            DarwinNotificationAction.text('reply', 'Ответить',
                buttonTitle: 'Отправить', placeholder: 'Сообщение'),
            DarwinNotificationAction.plain('dismiss', 'Закрыть'),
          ]),
          DarwinNotificationCategory(catCall, actions: [
            DarwinNotificationAction.plain('answer', 'Ответить'),
            DarwinNotificationAction.plain('decline', 'Отклонить',
                options: {DarwinNotificationActionOption.destructive}),
          ]),
          DarwinNotificationCategory(catFile, actions: [
            DarwinNotificationAction.plain('reveal', 'Показать в Finder'),
          ]),
        ],
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload ?? '';
        final i = p.indexOf('|');
        if (i < 0) return;
        onResponse?.call(p.substring(0, i), p.substring(i + 1), r.actionId, r.input);
      },
    );
  }

  static int idFor(String key) => key.hashCode & 0x7fffffff;

  Future<void> show({
    required String key,
    required String title,
    required String body,
    String? subtitle,
    String? category,
    required String payload,
    bool sound = true,
    String? thread,
  }) async {
    if (!enabled) return;
    try {
      await _plugin.show(
        id: idFor(key),
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          macOS: DarwinNotificationDetails(
            subtitle: subtitle,
            categoryIdentifier: category,
            threadIdentifier: thread,
            presentSound: sound,
            interruptionLevel:
                category == catCall ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancel(String key) async {
    try {
      await _plugin.cancel(id: idFor(key));
    } catch (_) {}
  }
}
