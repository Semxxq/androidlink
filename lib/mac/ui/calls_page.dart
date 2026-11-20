import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  final s = MacStore.instance;
  final _number = TextEditingController();
  bool _missedOnly = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Звонки'),
        actions: [
          ToolBarIconButton(
            label: _missedOnly ? 'Все' : 'Пропущенные',
            icon: MacosIcon(_missedOnly ? CupertinoIcons.list_bullet : CupertinoIcons.phone_arrow_down_left),
            showLabel: true,
            onPressed: () => setState(() => _missedOnly = !_missedOnly),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, sc) => ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final list = _missedOnly ? s.calls.where((c) => c.type == 'missed').toList() : s.calls;
              return Column(children: [
                if (s.liveCall != null) _LiveCallBar(call: s.liveCall!),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(children: [
                    Expanded(
                      child: MacosTextField(
                        controller: _number,
                        placeholder: 'Номер или имя',
                        prefix: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: MacosIcon(CupertinoIcons.phone, size: 14),
                        ),
                        enabled: s.connected,
                        onSubmitted: (_) => _dial(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PushButton(
                      controlSize: ControlSize.large,
                      onPressed: s.connected ? _dial : null,
                      child: const Text('Позвонить'),
                    ),
                  ]),
                ),
                Expanded(
                  child: list.isEmpty
                      ? EmptyState(
                          icon: CupertinoIcons.phone,
                          title: _missedOnly ? 'Нет пропущенных' : 'История звонков пуста',
                          subtitle: s.connected
                              ? 'Звонки появятся здесь. Разговор идёт через телефон.'
                              : 'Подключи телефон, чтобы видеть звонки',
                        )
                      : ListView.builder(
                          controller: sc,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          itemCount: list.length,
                          itemBuilder: (context, i) => _CallRow(call: list[i]),
                        ),
                ),
              ]);
            },
          ),
        ),
      ],
    );
  }

  void _dial() {
    final q = _number.text.trim();
    if (q.isEmpty) return;
    var number = q;
    if (!RegExp(r'\d').hasMatch(q)) {
      final c = s.contacts.where((c) => c.name.toLowerCase().contains(q.toLowerCase())).firstOrNull;
      if (c == null || c.numbers.isEmpty) return;
      number = c.numbers.first;
    }
    s.dial(number);
    _number.clear();
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call});
  final CallEntry call;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = MacStore.instance;
    final name = call.name ?? s.displayName(call.address);
    final missed = call.type == 'missed' || call.type == 'rejected';
    final (icon, label) = switch (call.type) {
      'outgoing' => (CupertinoIcons.phone_arrow_up_right, 'Исходящий'),
      'missed' => (CupertinoIcons.phone_arrow_down_left, 'Пропущенный'),
      'rejected' => (CupertinoIcons.phone_down, 'Отклонённый'),
      _ => (CupertinoIcons.phone_arrow_down_left, 'Входящий'),
    };
    return HoverTile(
      onTap: () => s.dial(call.address),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          Avatar(name, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: txt(context, w: FontWeight.w600, color: missed ? Pal.red : p.label)),
              Row(children: [
                Icon(icon, size: 12, color: p.secondary),
                const SizedBox(width: 4),
                Text(
                  [label, if (call.dur > 0) duration(call.dur), if (name != call.address) call.address]
                      .join(' · '),
                  style: txt(context, size: 11, color: p.secondary),
                ),
              ]),
            ]),
          ),
          Text(shortTime(call.time), style: txt(context, size: 11, color: p.secondary)),
          const SizedBox(width: 10),
          MacosTooltip(
            message: 'Позвонить',
            child: MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.phone_fill, size: 15, color: Pal.green),
              onPressed: s.connected ? () => s.dial(call.address) : null,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Banner across the top while a call is ringing or in progress.
class _LiveCallBar extends StatefulWidget {
  const _LiveCallBar({required this.call});
  final LiveCall call;
  @override
  State<_LiveCallBar> createState() => _LiveCallBarState();
}

class _LiveCallBarState extends State<_LiveCallBar> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.call;
    final s = MacStore.instance;
    final name = c.name ?? s.displayName(c.address);
    final ringing = c.state == 'ringing';
    final status = switch (c.state) {
      'ringing' => 'Входящий звонок…',
      'dialing' => 'Вызов…',
      _ => 'Разговор · ${duration(DateTime.now().difference(c.since).inSeconds)}',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1C7C3C), Color(0xFF30D158)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Avatar(name, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: txt(context, size: 15, w: FontWeight.w600, color: const Color(0xFFFFFFFF))),
            Text(status, style: txt(context, size: 12, color: const Color(0xDDFFFFFF))),
          ]),
        ),
        if (ringing) ...[
          _RoundButton(icon: CupertinoIcons.phone_down_fill, color: Pal.red, label: 'Отклонить',
              onTap: () => s.callAction('decline')),
          const SizedBox(width: 14),
          _RoundButton(icon: CupertinoIcons.phone_fill, color: const Color(0xFF34C759), label: 'Ответить',
              onTap: () => s.callAction('answer')),
        ] else
          _RoundButton(icon: CupertinoIcons.phone_down_fill, color: Pal.red, label: 'Завершить',
              onTap: () => s.callAction('end')),
      ]),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MacosTooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x55FFFFFF), width: 1.5),
          ),
          child: Icon(icon, color: const Color(0xFFFFFFFF), size: 19),
        ),
      ),
    );
  }
}
