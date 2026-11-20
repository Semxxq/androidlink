import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = MacStore.instance;
    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Уведомления'),
        actions: [
          ToolBarIconButton(
            label: 'Очистить всё',
            icon: const MacosIcon(CupertinoIcons.clear),
            showLabel: true,
            onPressed: () => s.clearNotifications(),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, sc) => ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              if (s.notifications.isEmpty) {
                return const EmptyState(
                  icon: CupertinoIcons.bell,
                  title: 'Нет уведомлений',
                  subtitle: 'Уведомления с телефона появятся здесь и в Центре уведомлений macOS. '
                      'Закрытое здесь закроется и на телефоне.',
                );
              }
              // group by app, newest app first
              final groups = <String, List<PhoneNotif>>{};
              for (final n in s.notifications) {
                groups.putIfAbsent(n.app, () => []).add(n);
              }
              return ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  for (final e in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 6),
                      child: Text(e.key, style: txt(context, size: 12, w: FontWeight.w600, color: Pal.of(context).secondary)),
                    ),
                    for (final n in e.value) _NotifCard(n: n),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotifCard extends StatefulWidget {
  const _NotifCard({required this.n});
  final PhoneNotif n;
  @override
  State<_NotifCard> createState() => _NotifCardState();
}

class _NotifCardState extends State<_NotifCard> {
  bool _replying = false;
  bool _hover = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final n = widget.n;
    final s = MacStore.instance;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.separator),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: Pal.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text(n.app.isEmpty ? '?' : n.app.characters.first.toUpperCase(),
                  style: txt(context, size: 15, w: FontWeight.w700, color: Pal.blue)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(n.title.isEmpty ? n.app : n.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: txt(context, w: FontWeight.w600)),
                  ),
                  Text(shortTime(n.time), style: txt(context, size: 11, color: p.secondary)),
                ]),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  SelectableText(n.body, style: txt(context, size: 12.5, color: p.label.withValues(alpha: 0.85))),
                ],
              ]),
            ),
            const SizedBox(width: 6),
            AnimatedOpacity(
              opacity: _hover ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: MacosIconButton(
                icon: MacosIcon(CupertinoIcons.xmark_circle_fill, size: 16, color: p.secondary),
                onPressed: () => s.dismissNotification(n.key),
              ),
            ),
          ]),
          if (n.canReply) ...[
            const SizedBox(height: 8),
            if (!_replying)
              Align(
                alignment: Alignment.centerLeft,
                child: PushButton(
                  controlSize: ControlSize.small,
                  secondary: true,
                  onPressed: s.connected ? () => setState(() => _replying = true) : null,
                  child: const Text('Ответить'),
                ),
              )
            else
              Row(children: [
                Expanded(
                  child: MacosTextField(
                    controller: _ctrl,
                    autofocus: true,
                    placeholder: 'Ответ в ${n.app}',
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                PushButton(controlSize: ControlSize.regular, onPressed: _send, child: const Text('Отправить')),
              ]),
          ],
        ]),
      ),
    );
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    MacStore.instance.replyNotification(widget.n.key, t);
    _ctrl.clear();
    setState(() => _replying = false);
  }
}
