import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ReplyBar extends StatefulWidget {
  const ReplyBar({
    super.key,
    required this.recipientName,
    required this.onSend,
  });

  final String recipientName;
  final void Function(String) onSend;

  @override
  State<ReplyBar> createState() => _ReplyBarState();
}

class _ReplyBarState extends State<ReplyBar> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _ctrl.clear();
    setState(() => _hasText = false);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color:        AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(color: AppTheme.divider, width: 0.5),
              ),
              child: TextField(
                controller:  _ctrl,
                focusNode:   _focus,
                maxLines:    null,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'SMS на ${widget.recipientName}...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onChanged:   (v) => setState(() => _hasText = v.trim().isNotEmpty),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedScale(
            scale:    _hasText ? 1.0 : 0.8,
            duration: const Duration(milliseconds: 150),
            child: AnimatedOpacity(
              opacity:  _hasText ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: _hasText ? _send : null,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _hasText ? AppTheme.accent : AppTheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.arrow_up, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
