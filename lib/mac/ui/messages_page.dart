import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final s = MacStore.instance;
  String? _selected; // thread key, or '' for "new message"
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    s.openThreadRequest.addListener(_openFromBanner);
  }

  @override
  void dispose() {
    s.openThreadRequest.removeListener(_openFromBanner);
    _search.dispose();
    super.dispose();
  }

  void _openFromBanner() {
    final k = s.openThreadRequest.value;
    if (k != null) setState(() => _selected = k);
  }

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Сообщения'),
        titleWidth: 200,
        actions: [
          ToolBarIconButton(
            label: 'Новое сообщение',
            icon: const MacosIcon(CupertinoIcons.square_pencil),
            showLabel: false,
            tooltipMessage: 'Новое сообщение',
            onPressed: s.connected ? () => setState(() => _selected = '') : null,
          ),
        ],
      ),
      children: [
        ResizablePane(
          minSize: 240,
          startSize: 300,
          maxSize: 420,
          resizableSide: ResizableSide.right,
          builder: (context, sc) => _threadList(context, sc),
        ),
        ContentArea(
          minWidth: 360,
          builder: (context, _) => ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              if (_selected == '') {
                return _NewChat(onPicked: (addr) => setState(() => _selected = s.newThread(addr)));
              }
              final t = _selected == null ? null : s.thread(_selected!);
              if (t == null) {
                return EmptyState(
                  icon: CupertinoIcons.chat_bubble_2,
                  title: s.threads.isEmpty ? 'Пока нет сообщений' : 'Выбери переписку',
                  subtitle: s.threads.isEmpty
                      ? (s.connected
                          ? (s.syncing ? 'Загружаем историю SMS с телефона…' : 'SMS с телефона появятся здесь')
                          : 'Подключи телефон, чтобы видеть SMS')
                      : null,
                );
              }
              return _Chat(key: ValueKey(t.key), thread: t);
            },
          ),
        ),
      ],
    );
  }

  Widget _threadList(BuildContext context, ScrollController sc) {
    final p = Pal.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: MacosSearchField(
          controller: _search,
          placeholder: 'Поиск',
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
      ),
      Expanded(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final all = s.threads.where((t) {
              if (_query.isEmpty) return true;
              final name = s.displayName(t.address).toLowerCase();
              return name.contains(_query) ||
                  t.address.contains(_query) ||
                  t.messages.any((m) => m.body.toLowerCase().contains(_query));
            }).toList();
            if (all.isEmpty) {
              return Center(
                child: Text(_query.isEmpty ? 'Нет переписок' : 'Ничего не найдено',
                    style: txt(context, color: p.secondary)),
              );
            }
            return ListView.builder(
              controller: sc,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: all.length,
              itemBuilder: (context, i) {
                final t = all[i];
                final sel = t.key == _selected;
                final last = t.last!;
                final name = s.displayName(t.address);
                final unread = t.unread;
                final fg = sel ? const Color(0xFFFFFFFF) : p.label;
                final fg2 = sel ? const Color(0xCCFFFFFF) : p.secondary;
                return HoverTile(
                  selected: sel,
                  onTap: () {
                    setState(() => _selected = t.key);
                    s.markRead(t.key);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(children: [
                      SizedBox(
                        width: 10,
                        child: unread > 0
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: Pal.blue, shape: BoxShape.circle))
                            : null,
                      ),
                      Avatar(name, size: 38),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: txt(context, w: FontWeight.w600, color: fg)),
                            ),
                            Text(shortTime(last.time), style: txt(context, size: 11, color: fg2)),
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            '${last.incoming ? '' : 'Вы: '}${last.body.isEmpty && last.image != null ? '📷 Фото' : last.body}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: txt(context, size: 12, color: fg2),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

// ── chat ─────────────────────────────────────────────────────────────────

class _Chat extends StatefulWidget {
  const _Chat({super.key, required this.thread});
  final SmsThread thread;
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final s = MacStore.instance;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      s.markRead(widget.thread.key);
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    s.sendSms(widget.thread.address, text);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.thread;
    final name = s.displayName(t.address);
    final msgs = t.messages;
    if (t.unread > 0) WidgetsBinding.instance.addPostFrameCallback((_) => s.markRead(t.key));

    return Column(children: [
      // header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.separator))),
        child: Row(children: [
          Avatar(name, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: txt(context, w: FontWeight.w600)),
              if (name != t.address) Text(t.address, style: txt(context, size: 11, color: p.secondary)),
            ]),
          ),
          MacosTooltip(
            message: 'Позвонить с телефона',
            child: MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.phone, size: 18),
              onPressed: s.connected ? () => s.dial(t.address) : null,
            ),
          ),
        ]),
      ),
      // bubbles
      Expanded(
        child: msgs.isEmpty
            ? EmptyState(icon: CupertinoIcons.chat_bubble, title: 'Новое сообщение', subtitle: 'Кому: $name')
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: msgs.length,
                itemBuilder: (context, ri) {
                  final i = msgs.length - 1 - ri;
                  final m = msgs[i];
                  final prev = i > 0 ? msgs[i - 1] : null;
                  final next = i < msgs.length - 1 ? msgs[i + 1] : null;
                  final showDay = prev == null || m.ts - prev.ts > 60 * 60 * 1000;
                  final tail = next == null || next.incoming != m.incoming || next.ts - m.ts > 60 * 1000;
                  final isLastOut = !m.incoming && msgs.skip(i + 1).every((x) => x.incoming);
                  return Column(children: [
                    if (showDay)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(dayHeader(m.time), style: txt(context, size: 11, color: p.secondary)),
                      ),
                    _Bubble(msg: m, tail: tail, showStatus: isLastOut),
                  ]);
                },
              ),
      ),
      // composer
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, e) {
                if (e is KeyDownEvent &&
                    e.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  _send();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: MacosTextField(
                controller: _ctrl,
                focusNode: _focus,
                enabled: s.connected,
                placeholder: s.connected ? 'SMS' : 'Телефон не подключён',
                minLines: 1,
                maxLines: 6,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: p.content,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.separator),
                ),
                focusedDecoration: BoxDecoration(
                  color: p.content,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Pal.blue.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder(
            valueListenable: _ctrl,
            builder: (context, v, _) {
              final can = v.text.trim().isNotEmpty && s.connected;
              return GestureDetector(
                onTap: can ? _send : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: can ? Pal.blue : p.tertiary, shape: BoxShape.circle),
                  child: const Icon(CupertinoIcons.arrow_up, size: 17, color: Color(0xFFFFFFFF)),
                ),
              );
            },
          ),
        ]),
      ),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.tail, required this.showStatus});
  final SmsMsg msg;
  final bool tail;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final out = !msg.incoming;
    final failed = msg.status == 'failed';
    final r = const Radius.circular(18);
    final small = const Radius.circular(5);
    return Padding(
      padding: EdgeInsets.only(bottom: tail ? 6 : 2),
      child: Column(
        crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: out ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (failed) const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(CupertinoIcons.exclamationmark_circle_fill, color: Pal.red, size: 18),
              ),
              Flexible(
                child: MacosTooltip(
                  message: dayHeader(msg.time),
                  child: GestureDetector(
                    onSecondaryTap: () => MacStore.instance.copy(msg.body),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 460),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: out ? (failed ? Pal.red.withValues(alpha: 0.85) : p.bubbleOut) : p.bubbleIn,
                        borderRadius: BorderRadius.only(
                          topLeft: r,
                          topRight: r,
                          bottomLeft: !out && tail ? small : r,
                          bottomRight: out && tail ? small : r,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!out && msg.sender != null && msg.address.contains(','))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(MacStore.instance.displayName(msg.sender!),
                                  style: txt(context, size: 11, w: FontWeight.w600, color: p.secondary)),
                            ),
                          if (msg.imageBytes != null)
                            Padding(
                              padding: EdgeInsets.only(bottom: msg.body.isEmpty ? 0 : 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
                                  child: Image.memory(msg.imageBytes!, fit: BoxFit.cover, gaplessPlayback: true),
                                ),
                              ),
                            ),
                          if (msg.body.isNotEmpty)
                            SelectableText(
                              msg.body,
                              style: txt(context, size: 13.5, color: out ? const Color(0xFFFFFFFF) : p.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (showStatus && msg.status != 'received')
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 4),
              child: Text(
                switch (msg.status) {
                  'sending' => 'Отправка…',
                  'failed' => 'Не отправлено',
                  _ => 'Отправлено',
                },
                style: txt(context, size: 10.5, color: failed ? Pal.red : p.secondary),
              ),
            ),
        ],
      ),
    );
  }
}

// ── new conversation ─────────────────────────────────────────────────────

class _NewChat extends StatefulWidget {
  const _NewChat({required this.onPicked});
  final void Function(String address) onPicked;
  @override
  State<_NewChat> createState() => _NewChatState();
}

class _NewChatState extends State<_NewChat> {
  final _ctrl = TextEditingController();
  final s = MacStore.instance;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final q = _ctrl.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? const <(String, String)>[]
        : [
            for (final c in s.contacts)
              for (final n in c.numbers)
                if (c.name.toLowerCase().contains(q) || n.contains(q)) (c.name, n),
          ].take(30).toList();
    final looksLikeNumber = RegExp(r'^\+?[\d\s()-]{3,}$').hasMatch(_ctrl.text.trim());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.separator))),
        child: Row(children: [
          Text('Кому:', style: txt(context, color: p.secondary)),
          const SizedBox(width: 8),
          Expanded(
            child: MacosTextField(
              controller: _ctrl,
              autofocus: true,
              placeholder: 'Имя или номер',
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) {
                if (matches.isNotEmpty) {
                  widget.onPicked(matches.first.$2);
                } else if (looksLikeNumber) {
                  widget.onPicked(v.trim());
                }
              },
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(8), children: [
          if (looksLikeNumber && matches.isEmpty)
            HoverTile(
              onTap: () => widget.onPicked(_ctrl.text.trim()),
              child: Row2(
                leading: Avatar(_ctrl.text.trim(), size: 30),
                title: 'Написать на ${_ctrl.text.trim()}',
              ),
            ),
          for (final (name, number) in matches)
            HoverTile(
              onTap: () => widget.onPicked(number),
              child: Row2(leading: Avatar(name, size: 30), title: name, subtitle: number),
            ),
          if (q.isEmpty && s.contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Контакты появятся после синхронизации с телефоном',
                  textAlign: TextAlign.center, style: txt(context, color: p.secondary)),
            ),
        ]),
      ),
    ]);
  }
}
