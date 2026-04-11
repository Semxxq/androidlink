import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../bridge/services/bridge_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

class ClipboardScreen extends StatefulWidget {
  const ClipboardScreen({super.key});

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  final List<_ClipItem> _history = [];

  @override
  void initState() {
    super.initState();
    BridgeService.instance.messages.listen((msg) {
      if (msg.type != AL.typeClipboard) return;
      final text = msg.payload['text'] as String? ?? '';
      if (text.isEmpty) return;
      setState(() {
        _history.insert(0, _ClipItem(text: text, fromAndroid: true));
      });
      // Авто-вставить в буфер Mac
      Clipboard.setData(ClipboardData(text: text));
    });
  }

  Future<void> _pushToAndroid() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    BridgeService.instance.sendRaw(
      {'text': data!.text!},
      AL.typeClipboard,
    );
    setState(() {
      _history.insert(0, _ClipItem(text: data.text!, fromAndroid: false));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Буфер обмена',
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              _ActionButton(
                label: 'Отправить на Android',
                icon:  CupertinoIcons.arrow_up_circle_fill,
                onTap: _pushToAndroid,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Скопировано на Android → появляется здесь автоматически',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          if (_history.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.doc_on_clipboard,
                        size: 48, color: AppTheme.textTertiary),
                    const SizedBox(height: 12),
                    const Text('Скопируй что-нибудь на Android',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (_, i) => _ClipTile(item: _history[i])
                    .animate().fadeIn(delay: (i * 20).ms),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClipItem {
  const _ClipItem({required this.text, required this.fromAndroid});
  final String text;
  final bool   fromAndroid;
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({required this.item});
  final _ClipItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            item.fromAndroid ? Icons.android : CupertinoIcons.desktopcomputer,
            size: 14, color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.text,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              maxLines: 3, overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
            color: AppTheme.textSecondary,
            onPressed: () => Clipboard.setData(ClipboardData(text: item.text)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.onTap});
  final String label; final IconData icon; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.accent),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppTheme.accent, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
