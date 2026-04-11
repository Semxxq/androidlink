import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import '../bridge/services/bridge_service.dart';
import '../../core/theme/app_theme.dart';

/// Android-приложение — минималистичное.
/// Главная задача: работать фоном и пересылать SMS/звонки на Mac.
class AndroidApp extends StatelessWidget {
  const AndroidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:           'AndroidLink',
      theme:           AppTheme.materialDark(),
      debugShowCheckedModeBanner: false,
      home: const AndroidMainScreen(),
    );
  }
}

class AndroidMainScreen extends StatefulWidget {
  const AndroidMainScreen({super.key});
  @override
  State<AndroidMainScreen> createState() => _AndroidMainScreenState();
}

class _AndroidMainScreenState extends State<AndroidMainScreen> {
  bool _smsGranted     = false;
  bool _callsGranted   = false;
  bool _notifGranted   = false;
  bool _showIpEntry    = false;
  final _ipCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final sms   = await Permission.sms.isGranted;
    final phone = await Permission.phone.isGranted;
    final notif = await Permission.notification.isGranted;
    setState(() {
      _smsGranted   = sms;
      _callsGranted = phone;
      _notifGranted = notif;
    });
  }

  Future<void> _requestAll() async {
    await [
      Permission.sms,
      Permission.phone,
      Permission.notification,
      Permission.contacts,
    ].request();
    await _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Лого
              Center(
                child: Column(children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accentGreen],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.android, color: Colors.white, size: 36),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 16),
                  const Text('AndroidLink',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary)),
                  const SizedBox(height: 6),
                  const Text('Твой Android на твоём Mac',
                    style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
                ]),
              ),

              const SizedBox(height: 40),

              // Статус подключения
              _ConnectionCard(),

              const SizedBox(height: 16),

              // Разрешения
              _PermissionsCard(
                smsGranted:   _smsGranted,
                callsGranted: _callsGranted,
                notifGranted: _notifGranted,
                onRequest:    _requestAll,
              ),

              const SizedBox(height: 16),

              // Ручной ввод IP
              _ManualIpCard(
                ctrl:     _ipCtrl,
                onConnect: () {
                  final ip = _ipCtrl.text.trim();
                  if (ip.isEmpty) return;
                  BridgeService.instance.connectToMacDirectly(ip);
                },
              ),

              const SizedBox(height: 32),

              // Инструкция
              const _HowItWorks(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Карточка статуса ──────────────────────────────────────────────────────
class _ConnectionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BridgeStatus>(
      stream:      BridgeService.instance.status,
      initialData: BridgeService.instance.currentStatus,
      builder:     (_, snap) {
        final status = snap.data!;
        final isConnected = status == BridgeStatus.connected;
        final (label, sub, color) = switch (status) {
          BridgeStatus.connected    => ('Подключено к Mac ✓',
              'SMS и звонки синхронизируются', AppTheme.accentGreen),
          BridgeStatus.connecting   => ('Подключение...', 'Устанавливаем соединение', AppTheme.accentOrange),
          BridgeStatus.searching    => ('Поиск Mac...', 'Убедись что на одном WiFi', AppTheme.accent),
          BridgeStatus.disconnected => ('Не подключено', 'Открой AndroidLink на Mac', AppTheme.textSecondary),
        };

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ).animate(onPlay: !isConnected ? (c) => c.repeat() : null)
             .fadeOut(duration: 600.ms).then().fadeIn(duration: 600.ms),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w600,
                    color: color, fontSize: 15)),
                Text(sub, style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
              ],
            )),
          ]),
        );
      },
    );
  }
}

// ── Разрешения ────────────────────────────────────────────────────────────
class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard({
    required this.smsGranted,
    required this.callsGranted,
    required this.notifGranted,
    required this.onRequest,
  });
  final bool smsGranted, callsGranted, notifGranted;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final allGranted = smsGranted && callsGranted && notifGranted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Разрешения', style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 16,
              color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          _PermRow(label: 'SMS', granted: smsGranted,
              desc: 'Читать и пересылать SMS'),
          _PermRow(label: 'Звонки', granted: callsGranted,
              desc: 'Caller ID и история'),
          _PermRow(label: 'Уведомления', granted: notifGranted,
              desc: 'Зеркалить на Mac'),
          if (!allGranted) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Разрешить всё'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({required this.label, required this.granted, required this.desc});
  final String label, desc;
  final bool   granted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(
          granted ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.xmark_circle_fill,
          color: granted ? AppTheme.accentGreen : AppTheme.accentRed,
          size: 18,
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 13,
              color: AppTheme.textPrimary)),
          Text(desc, style: const TextStyle(
              fontSize: 11, color: AppTheme.textSecondary)),
        ]),
      ]),
    );
  }
}

// ── Ручное подключение по IP ──────────────────────────────────────────────
class _ManualIpCard extends StatelessWidget {
  const _ManualIpCard({required this.ctrl, required this.onConnect});
  final TextEditingController ctrl;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ручное подключение', style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 16,
              color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          const Text('Если автопоиск не нашёл — введи IP Mac вручную',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller:   ctrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText:    '192.168.1.X',
                  hintStyle:   const TextStyle(color: AppTheme.textSecondary),
                  filled:      true,
                  fillColor:   AppTheme.surfaceHigh,
                  border:      OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              child: const Text('Connect'),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Как это работает ──────────────────────────────────────────────────────
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Как подключить', style: TextStyle(
              fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          ...[
            '1. Открой AndroidLink на Mac',
            '2. Подключи телефон и Mac к одному WiFi',
            '3. AndroidLink автоматически найдёт Mac',
            '4. Готово — SMS и звонки на Маке!',
          ].map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(s, style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary)),
          )),
        ],
      ),
    );
  }
}
