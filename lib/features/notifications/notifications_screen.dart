import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../bridge/services/bridge_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

class _NotifModel {
  const _NotifModel({
    required this.appName,
    required this.title,
    required this.body,
    required this.timestamp,
    this.iconUrl,
  });
  final String   appName;
  final String   title;
  final String   body;
  final DateTime timestamp;
  final String?  iconUrl;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_NotifModel> _notifs = [];

  @override
  void initState() {
    super.initState();
    BridgeService.instance.messages.listen((msg) {
      if (msg.type != AL.typeNotif) return;
      final n = _NotifModel(
        appName:   msg.payload['app']   as String? ?? 'Android',
        title:     msg.payload['title'] as String? ?? '',
        body:      msg.payload['body']  as String? ?? '',
        timestamp: DateTime.now(),
      );
      setState(() => _notifs.insert(0, n));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Уведомления',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
              const Spacer(),
              if (_notifs.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _notifs.clear()),
                  child: const Text('Очистить',
                      style: TextStyle(color: AppTheme.accent, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_notifs.isEmpty)
            Expanded(child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(CupertinoIcons.bell_slash, size: 48,
                    color: AppTheme.textTertiary),
                const SizedBox(height: 12),
                const Text('Нет уведомлений',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ]),
            ))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _notifs.length,
                itemBuilder: (_, i) {
                  final n = _notifs[i];
                  return Container(
                    margin:  const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.android, color: AppTheme.accentGreen, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(n.appName, style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary)),
                            const Spacer(),
                            Text(timeago.format(n.timestamp, locale: 'ru'),
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textSecondary)),
                          ]),
                          if (n.title.isNotEmpty)
                            Text(n.title, style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13,
                                color: AppTheme.textPrimary)),
                          if (n.body.isNotEmpty)
                            Text(n.body, style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      )),
                    ]),
                  ).animate().fadeIn(delay: (i * 20).ms);
                },
              ),
            ),
        ],
      ),
    );
  }
}
