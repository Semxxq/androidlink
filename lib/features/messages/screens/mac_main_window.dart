import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../calls/screens/calls_screen.dart';
import '../../clipboard/clipboard_screen.dart';
import '../../notifications/notifications_screen.dart';
import '../../files/files_screen.dart';
import '../screens/messages_screen.dart';
import '../../../features/bridge/services/bridge_service.dart';
import '../../../core/theme/app_theme.dart';

class MacMainWindow extends StatefulWidget {
  const MacMainWindow({super.key});
  @override
  State<MacMainWindow> createState() => _MacMainWindowState();
}

class _MacMainWindowState extends State<MacMainWindow> {
  int _index = 0;

  static const _items = [
    (icon: CupertinoIcons.chat_bubble_2_fill,     label: 'Сообщения'),
    (icon: CupertinoIcons.phone_fill,              label: 'Звонки'),
    (icon: CupertinoIcons.bell_fill,               label: 'Уведомления'),
    (icon: CupertinoIcons.doc_fill,                label: 'Файлы'),
    (icon: CupertinoIcons.doc_on_clipboard_fill,   label: 'Буфер обмена'),
  ];

  @override
  Widget build(BuildContext context) {
    return MacosWindow(
      sidebar: Sidebar(
        minWidth: 200,
        maxWidth: 260,
        decoration: const BoxDecoration(color: Color(0xFF161618)),
        builder: (ctx, _) => _SidebarContent(
          index:    _index,
          items:    _items,
          onSelect: (i) => setState(() => _index = i),
        ),
        bottom: const _StatusBar(),
      ),
      child: IndexedStack(
        index: _index,
        children: const [
          MessagesScreen(),
          CallsScreen(),
          NotificationsScreen(),
          FilesScreen(),
          ClipboardScreen(),
        ],
      ),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.index,
    required this.items,
    required this.onSelect,
  });

  final int index;
  final List<({IconData icon, String label})> items;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Лого
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.accent, AppTheme.accentGreen],
                  begin:  Alignment.topLeft,
                  end:    Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.android, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('AndroidLink', style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize:   16,
              color:      AppTheme.textPrimary,
            )),
          ]),
        ),

        // Nav items
        ...items.asMap().entries.map((e) {
          final isSelected = e.key == index;
          return GestureDetector(
            onTap: () => onSelect(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin:  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color:        isSelected ? AppTheme.accent.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(e.value.icon, size: 16,
                    color: isSelected ? AppTheme.accent : AppTheme.textSecondary),
                const SizedBox(width: 10),
                Text(e.value.label, style: TextStyle(
                  fontSize:   13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color:      isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                )),
              ]),
            ),
          );
        }),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BridgeStatus>(
      stream:      BridgeService.instance.status,
      initialData: BridgeService.instance.currentStatus,
      builder: (_, snap) {
        final s = snap.data ?? BridgeStatus.disconnected;
        final (label, color) = switch (s) {
          BridgeStatus.connected    => ('Android подключён', AppTheme.accentGreen),
          BridgeStatus.connecting   => ('Подключение...', AppTheme.accentOrange),
          BridgeStatus.searching    => ('Ожидание...', AppTheme.accent),
          BridgeStatus.disconnected => ('Не подключено', AppTheme.textSecondary),
        };
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 7, height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ).animate(
              onPlay: s == BridgeStatus.searching ? (c) => c.repeat() : null,
            ).fadeOut(duration: const Duration(milliseconds: 700))
             .then().fadeIn(duration: const Duration(milliseconds: 700)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ]),
        );
      },
    );
  }
}
