import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/call_model.dart';
import '../../../core/theme/app_theme.dart';

/// Нотификация входящего звонка — как на macOS когда звонит iPhone.
/// Появляется в правом верхнем углу.
class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({
    super.key,
    required this.call,
    required this.onDismiss,
  });

  final CallModel    call;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top:   20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: _CallCard(call: call, onDismiss: onDismiss)
            .animate()
            .slideX(begin: 1, duration: 400.ms, curve: Curves.easeOutCubic)
            .fadeIn(duration: 300.ms),
      ),
    );
  }
}

class _CallCard extends StatefulWidget {
  const _CallCard({required this.call, required this.onDismiss});
  final CallModel    call;
  final VoidCallback onDismiss;

  @override
  State<_CallCard> createState() => _CallCardState();
}

class _CallCardState extends State<_CallCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width:  320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        const Color(0xFF2C2C2E).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(
          color: AppTheme.glassBorder,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.4),
            blurRadius: 30,
            offset:     const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Иконка + "AndroidLink"
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentGreen],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.android,
                  color: Colors.white,
                  size:  16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'AndroidLink',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize:   13,
                  color:      AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onDismiss,
                child: const Icon(
                  CupertinoIcons.xmark,
                  size:  14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Аватар + имя
          Row(
            children: [
              _CallerAvatar(name: widget.call.displayName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.call.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize:   17,
                        color:      AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Входящий звонок · Android',
                      style: TextStyle(
                        fontSize: 12,
                        color:    AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      widget.call.address,
                      style: const TextStyle(
                        fontSize: 12,
                        color:    AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Кнопки (для macOS — только dismiss, ответить надо на телефоне)
          Row(
            children: [
              Expanded(
                child: _CallButton(
                  label: 'Отклонить',
                  color: AppTheme.accentRed,
                  icon:  CupertinoIcons.phone_down_fill,
                  onTap: widget.onDismiss,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CallButton(
                  label: 'Ответить',
                  color: AppTheme.accentGreen,
                  icon:  CupertinoIcons.phone_fill,
                  onTap: () {
                    // Отправляет команду на Android (ответить)
                    widget.onDismiss();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          const Text(
            'Ответить можно только на телефоне',
            style: TextStyle(
              fontSize: 10,
              color:    AppTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String       label;
  final Color        color;
  final IconData     icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
            color: color.withOpacity(0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:      color,
                fontWeight: FontWeight.w600,
                fontSize:   13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallerAvatar extends StatelessWidget {
  const _CallerAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accentGreen.withOpacity(0.3),
            AppTheme.accent.withOpacity(0.3),
          ],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize:   22,
            color:      AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}
