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
    final battery = d == null || d.battery < 0 ? '' : '${d.battery}%${d.charging ? ' ⚡︎' : ''}';
    final unread = s.unreadCount;
    final subtitle = [
      if (battery.isNotEmpty) 'Батарея $battery',
      if (unread > 0) 'Непрочитанных: $unread',
    ].join(' · ');
    final args = {'connected': d != null, 'title': d?.name ?? '', 'subtitle': subtitle};
    final key = args.toString();
    if (key == _last) return;
    _last = key;
    _ch.invokeMethod('update', args).catchError((Object _) {});
  }
}
