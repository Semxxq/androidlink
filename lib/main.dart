// MIT License — AndroidLink 2024

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'features/bridge/services/bridge_service.dart';
import 'features/android/android_bridge_service.dart';
import 'features/messages/screens/mac_main_window.dart';
import 'features/android/android_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size:            const Size(AL.minWindowWidth, AL.minWindowHeight),
        minimumSize:     const Size(AL.minWindowWidth, AL.minWindowHeight),
        center:          true,
        title:           'AndroidLink',
        titleBarStyle:   TitleBarStyle.hidden,
        backgroundColor: AppTheme.background,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  await BridgeService.instance.init();

  if (!Platform.isMacOS) {
    AndroidBridgeService.instance.start();
  }

  runApp(Platform.isMacOS ? const _MacApp() : const AndroidApp());
}

class _MacApp extends StatelessWidget {
  const _MacApp();
  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title:     'AndroidLink',
      theme:     AppTheme.macosTheme(),
      debugShowCheckedModeBanner: false,
      home:      const MacMainWindow(),
    );
  }
}
