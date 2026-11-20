import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:macos_ui/macos_ui.dart';

import '../features/bridge/services/bridge_service.dart';
import 'store.dart';
import 'ui/calls_page.dart';
import 'ui/clipboard_files_pages.dart';
import 'ui/common.dart';
import 'ui/devices_page.dart';
import 'ui/messages_page.dart';
import 'ui/notifications_page.dart';

class MacApp extends StatelessWidget {
  const MacApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'AndroidLink',
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Shell(),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final s = MacStore.instance;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    s.openThreadRequest.addListener(() => setState(() => _tab = 0));
    s.openTabRequest.addListener(() {
      final t = s.openTabRequest.value;
      if (t != null) setState(() => _tab = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final onboarding = BridgeService.instance.pairedDevices.isEmpty && !s.connected;
        return Stack(children: [
          MacosWindow(
            sidebar: Sidebar(
              minWidth: 210,
              startWidth: 230,
              maxWidth: 300,
              top: const _DeviceHeader(),
              builder: (context, sc) => SidebarItems(
                scrollController: sc,
                currentIndex: _tab,
                onChanged: (i) => setState(() => _tab = i),
                items: [
                  SidebarItem(
                    leading: const MacosIcon(CupertinoIcons.chat_bubble_fill),
                    label: const Text('Сообщения'),
                    trailing: _Badge(s.unreadCount),
                  ),
                  SidebarItem(
                    leading: const MacosIcon(CupertinoIcons.phone_fill),
                    label: const Text('Звонки'),
                    trailing: s.liveCall != null ? const _Dot(Pal.green) : null,
                  ),
                  SidebarItem(
                    leading: const MacosIcon(CupertinoIcons.bell_fill),
                    label: const Text('Уведомления'),
                    trailing: _Badge(s.notifications.length, muted: true),
                  ),
                  const SidebarItem(
                    leading: MacosIcon(CupertinoIcons.doc_on_clipboard_fill),
                    label: Text('Буфер обмена'),
                  ),
                  const SidebarItem(
                    leading: MacosIcon(CupertinoIcons.folder_fill),
                    label: Text('Файлы'),
                  ),
                  const SidebarItem(
                    leading: MacosIcon(CupertinoIcons.device_phone_portrait),
                    label: Text('Устройства'),
                  ),
                ],
              ),
              bottom: const _SidebarActions(),
            ),
            child: onboarding
                ? const DevicesPage(onboarding: true)
                : IndexedStack(index: _tab, children: const [
                    MessagesPage(),
                    CallsPage(),
                    NotificationsPage(),
                    ClipboardPage(),
                    FilesPage(),
                    DevicesPage(),
                  ]),
          ),
          if (s.toast != null)
            Positioned(
              bottom: 22,
              left: 0,
              right: 0,
              child: Center(child: _Toast(s.toast!)),
            ),
        ]);
      },
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader();

  @override
  Widget build(BuildContext context) {
    // const instance: rebuild on store changes ourselves.
    return ListenableBuilder(listenable: MacStore.instance, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final s = MacStore.instance;
    final p = Pal.of(context);
    final d = s.device;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.hover, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: d != null
                    ? const [Color(0xFF3390FF), Color(0xFF734DF2)]
                    : const [Color(0xFF9A9AA0), Color(0xFFBDBDC2)],
              ),
              boxShadow: [
                if (d != null) BoxShadow(color: const Color(0xFF3390FF).withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: const Center(child: MacosIcon(CupertinoIcons.device_phone_portrait, size: 20, color: Color(0xFFFFFFFF))),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.hover, width: 2)),
              child: _Dot(d != null ? Pal.green : const Color(0xFF8E8E93), size: 10),
            ),
          ),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d?.name ?? 'Нет телефона',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: txt(context, w: FontWeight.w600)),
            const SizedBox(height: 1),
            if (d == null)
              Text('Ожидание подключения…', style: txt(context, size: 11, color: p.secondary))
            else
              Row(children: [
                if (d.battery >= 0) ...[
                  _Battery(level: d.battery, charging: d.charging),
                  const SizedBox(width: 5),
                  Text('${d.battery}%', style: txt(context, size: 11, color: p.secondary)),
                ] else ...[
                  const _Battery(level: 0, charging: false),
                  const SizedBox(width: 5),
                  Text('0%', style: txt(context, size: 11, color: p.secondary)),
                ],
                const SizedBox(width: 6),
                Text('· ${s.unreadCount} SMS', style: txt(context, size: 11, color: p.secondary)),
                if (s.syncing) ...[
                  const SizedBox(width: 6),
                  const SizedBox(width: 10, height: 10, child: ProgressCircle(radius: 5)),
                ],
              ]),
          ]),
        ),
      ]),
    );
  }
}

class _SidebarActions extends StatelessWidget {
  const _SidebarActions();
  @override
  Widget build(BuildContext context) {
    // const instance: rebuild on store changes ourselves.
    return ListenableBuilder(listenable: MacStore.instance, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final s = MacStore.instance;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Expanded(
          child: PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: s.connected ? s.ring : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MacosIcon(s.ringing ? CupertinoIcons.stop_fill : CupertinoIcons.speaker_3_fill, size: 13),
              const SizedBox(width: 6),
              Text(s.ringing ? 'Остановить звук' : 'Найти телефон'),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.level, required this.charging});
  final int level;
  final bool charging;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final color = charging ? Pal.green : (level <= 20 ? Pal.red : p.label);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 20,
        height: 10,
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          border: Border.all(color: p.secondary, width: 1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (level / 100).clamp(0.05, 1.0),
            child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5))),
          ),
        ),
      ),
      Container(width: 1.5, height: 4, color: p.secondary),
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.count, {this.muted = false});
  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: muted ? Pal.of(context).tertiary : Pal.blue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(count > 99 ? '99+' : '$count',
          style: txt(context, size: 10.5, w: FontWeight.w600, color: const Color(0xFFFFFFFF))),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, {this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Pal.of(context).content, width: 1.5),
        ),
      );
}

class _Toast extends StatelessWidget {
  const _Toast(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xEE2C2C2E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Text(text, style: txt(context, color: const Color(0xFFFFFFFF))),
    );
  }
}
