import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/message.dart';
import '../../../core/theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});
  final SmsModel message;

  @override
  Widget build(BuildContext context) {
    final isOut = !message.isIncoming;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            isOut ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isOut) const Spacer(flex: 2),
          Flexible(
            flex: 5,
            child: Column(
              crossAxisAlignment:
                  isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: isOut
                        ? AppTheme.messageBubble
                        : AppTheme.messageBubbleIn,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isOut ? 18 : 4),
                      bottomRight: Radius.circular(isOut ? 4 : 18),
                    ),
                  ),
                  child: Text(
                    message.body,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize:   14,
                      color:      AppTheme.textPrimary,
                      height:     1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.timestamp),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (isOut) ...[
                      const SizedBox(width: 4),
                      _StatusIcon(status: message.status),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!isOut) const Spacer(flex: 2),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final SmsStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      SmsStatus.sending   => const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppTheme.textSecondary,
          ),
        ),
      SmsStatus.delivered => const Icon(
          Icons.done_all,
          size: 12,
          color: AppTheme.accentGreen,
        ),
      SmsStatus.failed    => const Icon(
          Icons.error_outline,
          size: 12,
          color: AppTheme.accentRed,
        ),
    };
  }
}
