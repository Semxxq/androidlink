import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'store.dart';

/// Keeps the native menu-bar item (AppDelegate.swift) in sync with the store.
class TrayBridge {
  TrayBridge._();
  static final TrayBridge instance = TrayBridge._();

  static const _ch = MethodChannel('androidlink/tray');
  String _last = '';

  void start() {
    final s = MacStore.instance;
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'action') return;
      switch ((call.arguments as Map)['id']) {
        case 'ring':
          s.ring();
        case 'clipboard':
          await s.pushClipboard();
        case 'sendFile':
          final files = await FilePicker.pickFiles();
          final paths = files.map((f) => f.path).whereType<String>();
          await s.sendFiles(paths.map(File.new).toList());
      }
    });
    s.addListener(_update);
    _update();
  }

  void _update() {
    final s = MacStore.instance;
    final d = s.device;
    final args = {
      'connected': d != null,
      'title': d?.name ?? '',
      'battery': d?.battery ?? -1,
      'charging': d?.charging ?? false,
      'unread': s.unreadCount,
      'notifs': s.notifications.length,
      'missed': s.calls.where((c) => c.type == 'missed' && DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(c.ts)).inHours < 24).length,
      'syncing': s.syncing,
    };
    final key = args.toString();
    if (key == _last) return;
    _last = key;
    _ch.invokeMethod('update', args).catchError((Object _) {});
  }
}
