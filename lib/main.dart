// AndroidLink — Continuity for Android + Mac.

import 'dart:io';

import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:macos_ui/macos_ui.dart';

import 'android/android_app.dart';
import 'features/bridge/services/bridge_service.dart';
import 'mac/mac_app.dart';
import 'mac/notifier.dart';
import 'mac/store.dart';
import 'mac/tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  FlutterCryptography.enable(); // native AES-GCM (CryptoKit / javax.crypto)

  if (Platform.isMacOS) {
    await MacosWindowUtilsConfig().apply();
    await MacNotifier.instance.init();
    await BridgeService.instance.init();
    await MacStore.instance.init();
    TrayBridge.instance.start();
    runApp(const MacApp());
  } else {
    await BridgeService.instance.init();
    runApp(const AndroidApp());
  }
}
