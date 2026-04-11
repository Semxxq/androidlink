import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/message.dart';
import '../widgets/message_bubble.dart';
import '../widgets/reply_bar.dart';
import '../../bridge/services/bridge_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final Map<String, SmsThread> _threads = {};
  SmsThread? _selectedThread;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _listenToBridge();
  }

  void _listenToBridge() {
    BridgeService.instance.messages.listen((msg) {
      if (msg.type != AL.typeSms) return;
      final sms = SmsModel.fromMap(msg.payload);
      setState(() {
        final thread = _threads[sms.address];
        if (thread == null) {
          _threads[sms.address] = SmsThread(
            address:  sms.address,
            messages: [sms],
          );
        } else {
          _threads[sms.address] = thread.copyWith(
            messages: [...thread.messages, sms],
          );
        }
        // Если открыт этот тред — скролл вниз
        if (_selectedThread?.address == sms.address) {
          _selectedThread = _threads[sms.address];
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(
                _scrollCtrl.position.maxScrollExtent,
                duration: 300.ms,
                curve: Curves.easeOut,
              );
            }
          });
        }
      });
    });
  }

  void _sendReply(String text) {
    if (_selectedThread == null || text.isEmpty) return;
    BridgeService.instance.sendRaw({
      'address': _selectedThread!.address,
      'body':    text,
    }, AL.typeSmsReply);

    // Оптимистично добавляем в UI
    final sent = SmsModel(
      id:         DateTime.now().toIso8601String(),
      address:    _selectedThread!.address,
      body:       text,
      timestamp:  DateTime.now(),
      isIncoming: false,
      status:     SmsStatus.sending,
    );
    setState(() {
      final thread = _threads[_selectedThread!.address]!;
      _threads[_selectedThread!.address] = thread.copyWith(
        messages: [...thread.messages, sent],
      );
      _selectedThread = _threads[_selectedThread!.address];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Список тредов (левая панель) ─────────────────────────────
        SizedBox(
          width: AL.sidebarWidth,
          child: _ThreadList(
            threads:  _threads.values.toList()
              ..sort((a, b) => (b.lastMessage?.timestamp ?? DateTime(0))
                  .compareTo(a.lastMessage?.timestamp ?? DateTime(0))),
            selected: _selectedThread,
            onSelect: (t) => setState(() => _selectedThread = t),
          ),
        ),

        // ── Разделитель ───────────────────────────────────────────────
        Container(width: 0.5, color: AppTheme.divider),

        // ── Чат (правая панель) ───────────────────────────────────────
        Expanded(
          child: _selectedThread == null
              ? const _EmptyChat()
              : _ChatView(
                  thread:     _selectedThread!,
                  scrollCtrl: _scrollCtrl,
                  onSend:     _sendReply,
                ),
        ),
      ],
    );
  }
}

// ── Список тредов ─────────────────────────────────────────────────────────
class _ThreadList extends StatelessWidget {
  const _ThreadList({
    required this.threads,
    required this.selected,
    required this.onSelect,
  });

  final List<SmsThread> threads;
  final SmsThread?      selected;
  final void Function(SmsThread) onSelect;

  @override
  Widget build(BuildContext context) {
    if (threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.chat_bubble_2,
              size: 40,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'Нет сообщений',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: threads.length,
      itemBuilder: (_, i) {
        final t = threads[i];
        final isSelected = selected?.address == t.address;
        return _ThreadTile(
          thread:     t,
          isSelected: isSelected,
          onTap:      () => onSelect(t),
        ).animate().fadeIn(delay: (i * 30).ms);
      },
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.isSelected,
    required this.onTap,
  });

  final SmsThread thread;
  final bool      isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final last = thread.lastMessage;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 150.ms,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // Аватар
            _Avatar(name: thread.displayName),
            const SizedBox(width: 10),
            // Текст
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.displayName,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (last != null)
                        Text(
                          timeago.format(last.timestamp, locale: 'ru'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          last?.body ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: thread.unreadCount > 0
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                            fontWeight: thread.unreadCount > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (thread.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: const BoxDecoration(
                            color:  AppTheme.accent,
                            shape:  BoxShape.circle,
                          ),
                          child: Text(
                            '${thread.unreadCount}',
                            style: const TextStyle(
                              color:    Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final colors   = [
      AppTheme.accent,
      AppTheme.accentGreen,
      const Color(0xFFBF5AF2),
      const Color(0xFFFF6B6B),
    ];
    final color = colors[name.hashCode.abs() % colors.length];

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color:  color.withOpacity(0.2),
        shape:  BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color:      color,
            fontWeight: FontWeight.bold,
            fontSize:   15,
          ),
        ),
      ),
    );
  }
}

// ── Чат ──────────────────────────────────────────────────────────────────
class _ChatView extends StatelessWidget {
  const _ChatView({
    required this.thread,
    required this.scrollCtrl,
    required this.onSend,
  });

  final SmsThread   thread;
  final ScrollController scrollCtrl;
  final void Function(String) onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        _ChatHeader(thread: thread),
        const Divider(height: 0.5, color: AppTheme.divider),

        // Сообщения
        Expanded(
          child: ListView.builder(
            controller: scrollCtrl,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            itemCount: thread.messages.length,
            itemBuilder: (_, i) {
              final msg  = thread.messages[i];
              final prev = i > 0 ? thread.messages[i - 1] : null;
              final showDate = prev == null ||
                  !_sameDay(prev.timestamp, msg.timestamp);
              return Column(
                children: [
                  if (showDate) _DateDivider(date: msg.timestamp),
                  MessageBubble(message: msg)
                      .animate()
                      .slideY(begin: 0.2, duration: 200.ms)
                      .fadeIn(duration: 200.ms),
                ],
              );
            },
          ),
        ),

        // Reply bar
        ReplyBar(
          recipientName: thread.displayName,
          onSend: onSend,
        ),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.thread});
  final SmsThread thread;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _Avatar(name: thread.displayName),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                thread.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                thread.address,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now   = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    final label = isToday
        ? 'Сегодня'
        : '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppTheme.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppTheme.divider)),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.chat_bubble_text,
            size: 64,
            color: AppTheme.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Выбери переписку',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'SMS с твоего Android здесь',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
