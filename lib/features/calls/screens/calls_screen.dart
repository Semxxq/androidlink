import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/call_model.dart';
import '../../bridge/services/bridge_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../widgets/incoming_call_overlay.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final List<CallModel> _calls = [];
  CallModel? _activeCall;
  OverlayEntry? _callOverlay;

  @override
  void initState() {
    super.initState();
    _listenToBridge();
  }

  void _listenToBridge() {
    BridgeService.instance.messages.listen((msg) {
      if (msg.type != AL.typeCall) return;
      final call = CallModel.fromMap(msg.payload);

      setState(() {
        if (call.isActive) {
          _activeCall = call;
          _showIncomingCallOverlay(call);
        } else {
          _activeCall = null;
          _removeCallOverlay();
          _calls.insert(0, call);
        }
      });
    });
  }

  void _showIncomingCallOverlay(CallModel call) {
    _removeCallOverlay();
    _callOverlay = OverlayEntry(
      builder: (_) => IncomingCallOverlay(
        call:       call,
        onDismiss:  _removeCallOverlay,
      ),
    );
    Overlay.of(context).insert(_callOverlay!);
  }

  void _removeCallOverlay() {
    _callOverlay?.remove();
    _callOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: const Text(
            'Звонки',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize:   28,
              fontWeight: FontWeight.bold,
              color:      AppTheme.textPrimary,
            ),
          ),
        ),

        // Active call banner
        if (_activeCall != null)
          _ActiveCallBanner(call: _activeCall!)
              .animate()
              .slideY(begin: -1, duration: 300.ms)
              .fadeIn(),

        // История
        if (_calls.isEmpty)
          Expanded(child: _EmptyCallLog())
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _calls.length,
              itemBuilder: (_, i) => _CallTile(call: _calls[i])
                  .animate()
                  .fadeIn(delay: (i * 20).ms),
            ),
          ),
      ],
    );
  }
}

// ── Баннер активного звонка ───────────────────────────────────────────────
class _ActiveCallBanner extends StatelessWidget {
  const _ActiveCallBanner({required this.call});
  final CallModel call;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:        AppTheme.accentGreen.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(
          color: AppTheme.accentGreen.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.accentGreen,
              shape: BoxShape.circle,
            ),
          ).animate(onPlay: (c) => c.repeat())
           .scale(end: const Offset(1.5, 1.5), duration: 800.ms)
           .then()
           .scale(end: const Offset(1.0, 1.0), duration: 800.ms),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Звонок: ${call.displayName}',
              style: const TextStyle(
                color:      AppTheme.accentGreen,
                fontWeight: FontWeight.w600,
                fontSize:   14,
              ),
            ),
          ),
          Text(
            call.address,
            style: const TextStyle(
              color:   AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Строка истории звонков ────────────────────────────────────────────────
class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});
  final CallModel call;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (call.type) {
      CallType.incoming => (CupertinoIcons.phone_arrow_down_left,  AppTheme.accentGreen),
      CallType.outgoing => (CupertinoIcons.phone_arrow_up_right,   AppTheme.accent),
      CallType.missed   => (CupertinoIcons.phone_arrow_down_left,  AppTheme.accentRed),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color:        AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize:   14,
                    color:      call.type == CallType.missed
                        ? AppTheme.accentRed
                        : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  call.address,
                  style: const TextStyle(
                    fontSize: 11,
                    color:    AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeago.format(call.timestamp, locale: 'ru'),
                style: const TextStyle(
                  fontSize: 11,
                  color:    AppTheme.textSecondary,
                ),
              ),
              if (call.duration != null)
                Text(
                  _formatDuration(call.duration!),
                  style: const TextStyle(
                    fontSize: 11,
                    color:    AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}ч ${d.inMinutes.remainder(60)}м';
    if (d.inMinutes > 0) return '${d.inMinutes}м ${d.inSeconds.remainder(60)}с';
    return '${d.inSeconds}с';
  }
}

class _EmptyCallLog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.phone,
            size:  48,
            color: AppTheme.textTertiary,
          ),
          const SizedBox(height: 12),
          const Text(
            'Нет звонков',
            style: TextStyle(
              fontSize:   17,
              fontWeight: FontWeight.w600,
              color:      AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Входящие звонки на Android\nбудут показаны здесь',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color:    AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
