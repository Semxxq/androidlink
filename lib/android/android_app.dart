import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/bridge/services/bridge_service.dart';
import 'android_bridge.dart';

/// Android companion app — Material You. The heavy lifting runs in the
/// native LinkService; this UI pairs, shows status and fixes permissions.
class AndroidApp extends StatefulWidget {
  const AndroidApp({super.key});
  @override
  State<AndroidApp> createState() => _AndroidAppState();
}

class _AndroidAppState extends State<AndroidApp> {
  /// Material You: seed from the system wallpaper accent (Android 12+).
  Color _seed = const Color(0xFF0A84FF);

  @override
  void initState() {
    super.initState();
    AndroidBridgeService.instance.systemAccent().then((c) {
      if (c != null && mounted) setState(() => _seed = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'AndroidLink',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final b = BridgeService.instance;
  final a = AndroidBridgeService.instance;

  Map<String, bool> _perms = {};
  final Map<String, Map<String, dynamic>> _transfers = {};
  StreamSubscription? _tSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _tSub = b.nativeTransfers.listen((t) {
      setState(() => _transfers[t['fid'] as String] = t);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final p = {
      'sms': await Permission.sms.isGranted,
      'phone': await Permission.phone.isGranted,
      'contacts': await Permission.contacts.isGranted,
      'notif': await Permission.notification.isGranted,
      'listener': await a.isNotificationListenerEnabled(),
      'battery': await a.isBatteryExempt(),
    };
    if (mounted) setState(() => _perms = p);
  }

  Future<void> _fix(String key) async {
    switch (key) {
      case 'sms':
        await _request(Permission.sms);
      case 'phone':
        await _request(Permission.phone);
      case 'contacts':
        await _request(Permission.contacts);
      case 'notif':
        await _request(Permission.notification);
      case 'listener':
        await a.openNotificationSettings();
      case 'battery':
        await a.requestBatteryExemption();
    }
    await _refresh();
  }

  Future<void> _request(Permission p) async {
    final st = await p.request();
    if (st.isPermanentlyDenied) await a.openAppSettings();
  }

  Future<void> _sendFiles() async {
    final files = await FilePicker.pickFiles();
    final paths = files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    await b.sendFiles(paths);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: StreamBuilder<BridgeStatus>(
        stream: b.status,
        initialData: b.currentStatus,
        builder: (context, st) => StreamBuilder<String?>(
          stream: b.pairingIssue,
          builder: (context, issue) => StreamBuilder<String?>(
            stream: b.peerName,
            builder: (context, name) {
              final status = st.data ?? BridgeStatus.disconnected;
              final paired = issue.data != 'unpaired';
              final connected = status == BridgeStatus.connected;
              return CustomScrollView(slivers: [
                SliverAppBar.large(
                  title: const Text('AndroidLink'),
                  actions: [
                    if (paired)
                      PopupMenuButton<String>(
                        onSelected: (v) => v == 'ip' ? _manualIp() : _unpair(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'ip', child: Text('Подключить по IP')),
                          PopupMenuItem(value: 'unpair', child: Text('Отвязать Mac')),
                        ],
                      ),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList.list(children: [
                    if (!paired)
                      _PairHero(onScan: _scan)
                    else
                      _StatusCard(status: status, issue: issue.data, macName: name.data, onRescan: _scan),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.content_paste_go_rounded,
                          label: 'Буфер → Mac',
                          enabled: connected,
                          onTap: () async {
                            await a.pushClipboardToMac();
                            if (context.mounted) _snack(context, 'Буфер отправлен на Mac');
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.upload_file_rounded,
                          label: 'Файл → Mac',
                          enabled: connected,
                          onTap: _sendFiles,
                        ),
                      ),
                    ]),
                    if (_transfers.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _TransfersCard(transfers: _transfers.values.toList().reversed.toList()),
                    ],
                    const SizedBox(height: 24),
                    _PermissionsCard(perms: _perms, onFix: _fix),
                    const SizedBox(height: 16),
                    _TipsCard(cs: cs),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _scan() async {
    final qr = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (qr == null || !mounted) return;
    final ok = await b.connectViaQr(qr);
    if (!mounted) return;
    _snack(context, ok ? 'Сопряжено — подключаемся к Mac' : 'Это не QR-код AndroidLink');
    if (ok) {
      // First pairing: ask for everything the sync needs.
      if (_perms.values.any((v) => !v)) {
        await [Permission.sms, Permission.phone, Permission.contacts, Permission.notification].request();
        await _refresh();
      }
    }
  }

  Future<void> _manualIp() async {
    final ctrl = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Подключить по IP'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '192.168.1.10', labelText: 'IP-адрес Mac'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Подключить')),
        ],
      ),
    );
    if (ip == null || ip.isEmpty) return;
    await b.connectToMacDirectly(ip);
  }

  Future<void> _unpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.link_off_rounded),
        title: const Text('Отвязать Mac?'),
        content: const Text('Синхронизация остановится. Чтобы подключиться снова, отсканируй QR-код на Mac.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton.tonal(onPressed: () => Navigator.pop(c, true), child: const Text('Отвязать')),
        ],
      ),
    );
    if (ok == true) await b.unpair();
  }

  void _snack(BuildContext context, String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), behavior: SnackBarBehavior.floating));
}

// ── widgets ──────────────────────────────────────────────────────────────

class _PairHero extends StatelessWidget {
  const _PairHero({required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.laptop_mac_rounded, size: 48, color: cs.onPrimaryContainer),
          const SizedBox(height: 16),
          Text('Подключи свой Mac', style: tt.headlineSmall?.copyWith(color: cs.onPrimaryContainer)),
          const SizedBox(height: 8),
          Text(
            'Открой AndroidLink на Mac и отсканируй QR-код. Связь идёт напрямую по Wi-Fi и шифруется.',
            style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Сканировать QR-код'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ]),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.issue, required this.macName, required this.onRescan});
  final BridgeStatus status;
  final String? issue;
  final String? macName;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mac = macName ?? 'Mac';
    final (title, sub, bg, fg, icon) = switch (status) {
      BridgeStatus.connected => (
          mac,
          'Подключено · работает в фоне',
          cs.primaryContainer,
          cs.onPrimaryContainer,
          Icons.laptop_mac_rounded
        ),
      BridgeStatus.connecting => (mac, 'Подключение…', cs.secondaryContainer, cs.onSecondaryContainer, Icons.sync_rounded),
      BridgeStatus.searching =>
        (mac, 'Ищем Mac в сети…', cs.surfaceContainerHighest, cs.onSurface, Icons.wifi_find_rounded),
      BridgeStatus.disconnected => issue == 'unauthorized'
          ? (mac, 'Mac не узнал телефон — отсканируй QR заново', cs.errorContainer, cs.onErrorContainer,
              Icons.gpp_maybe_rounded)
          : (mac, 'Не подключено', cs.surfaceContainerHighest, cs.onSurface, Icons.laptop_mac_rounded),
    };
    return Card(
      elevation: 0,
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: fg.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: fg, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tt.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(children: [
                  if (status == BridgeStatus.connected)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle),
                    ),
                  if (status == BridgeStatus.searching || status == BridgeStatus.connecting)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                          width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                    ),
                  Flexible(child: Text(sub, style: tt.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.8)))),
                ]),
              ]),
            ),
          ]),
          if (issue == 'unauthorized') ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRescan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Сканировать снова'),
            ),
          ],
          if (status != BridgeStatus.connected) ...[
            const SizedBox(height: 12),
            StreamBuilder<String>(
              stream: BridgeService.instance.diag,
              builder: (context, d) => (d.data ?? '').isEmpty
                  ? const SizedBox.shrink()
                  : Text(d.data!, style: tt.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85), fontFamily: 'monospace')),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showDiagnostics(context),
                icon: const Icon(Icons.troubleshoot_rounded, size: 18),
                label: const Text('Диагностика'),
                style: TextButton.styleFrom(foregroundColor: fg),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

Future<void> _showDiagnostics(BuildContext context) async {
  final d = await BridgeService.instance.diagnostics();
  if (!context.mounted) return;
  final beacon = (d['beaconAgo'] as num?)?.toInt() ?? -1;
  final text = [
    'Статус: ${d['status']}',
    'Адреса Mac из QR: ${d['hosts'] ?? '—'}',
    'Адреса телефона: ${d['localIps'] ?? '—'}',
    'Сигнал Mac (UDP): ${beacon < 0 ? 'ни разу не получен' : '$beacon с назад'}',
    'Последняя ошибка: ${(d['diag'] as String?)?.isNotEmpty == true ? d['diag'] : '—'}',
  ].join('\n');
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Диагностика'),
      content: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Закрыть'))],
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.enabled, required this.onTap});
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      color: cs.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(children: [
              Icon(icon, size: 28, color: cs.primary),
              const SizedBox(height: 10),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TransfersCard extends StatelessWidget {
  const _TransfersCard({required this.transfers});
  final List<Map<String, dynamic>> transfers;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Column(children: [
        for (final t in transfers.take(5))
          ListTile(
            leading: Icon(t['dir'] == 'in' ? Icons.download_rounded : Icons.upload_rounded),
            title: Text(t['name'] as String? ?? 'файл', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: t['failed'] == true
                ? const Text('Ошибка передачи')
                : t['finished'] == true
                    ? Text(t['dir'] == 'in' ? 'Сохранено в Download/AndroidLink' : 'Отправлено на Mac')
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(
                          value: (t['size'] as num? ?? 0) > 0
                              ? ((t['done'] as num? ?? 0) / (t['size'] as num)).clamp(0, 1).toDouble()
                              : null,
                        ),
                      ),
          ),
      ]),
    );
  }
}

class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard({required this.perms, required this.onFix});
  final Map<String, bool> perms;
  final void Function(String) onFix;

  static const _items = [
    ('sms', Icons.sms_rounded, 'SMS', 'Читать и отправлять сообщения с Mac'),
    ('phone', Icons.call_rounded, 'Звонки', 'Кто звонит, ответить и позвонить с Mac'),
    ('contacts', Icons.contacts_rounded, 'Контакты', 'Имена вместо номеров'),
    ('notif', Icons.notifications_rounded, 'Уведомления', 'Значок подключения в шторке'),
    ('listener', Icons.notifications_active_rounded, 'Доступ к уведомлениям', 'Показывать уведомления на Mac'),
    ('battery', Icons.battery_saver_rounded, 'Работа в фоне', 'Чтобы система не обрывала связь'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final missing = _items.where((i) => perms[i.$1] == false).toList();
    final done = perms.isNotEmpty && missing.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('Разрешения', style: tt.titleMedium),
      ),
      Card.filled(
        color: cs.surfaceContainerHigh,
        child: done
            ? ListTile(
                leading: Icon(Icons.verified_rounded, color: cs.primary),
                title: const Text('Всё настроено'),
                subtitle: const Text('Телефон синхронизируется полностью'),
              )
            : Column(children: [
                for (final i in _items)
                  ListTile(
                    leading: Icon(i.$2, color: perms[i.$1] == true ? cs.primary : cs.onSurfaceVariant),
                    title: Text(i.$3),
                    subtitle: Text(i.$4),
                    trailing: perms[i.$1] == true
                        ? Icon(Icons.check_circle_rounded, color: cs.primary)
                        : FilledButton.tonal(onPressed: () => onFix(i.$1), child: const Text('Включить')),
                  ),
                if (perms['listener'] == false)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'Если переключатель серый: Настройки → Приложения → AndroidLink → ⋮ → '
                      '«Разрешить ограниченные настройки».',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
              ]),
      ),
    ]);
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget tip(IconData i, String t, String s) => ListTile(
          leading: Icon(i, color: cs.tertiary),
          title: Text(t),
          subtitle: Text(s),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text('Как пользоваться', style: tt.titleMedium)),
      Card.outlined(
        child: Column(children: [
          tip(Icons.content_copy_rounded, 'Общий буфер',
              'Скопированное на Mac сразу здесь. Отсюда — кнопка «Буфер → Mac» в шторке или плитка в быстрых настройках.'),
          tip(Icons.share_rounded, 'Поделиться → Отправить на Mac', 'Фото, файлы и ссылки из любого приложения.'),
          tip(Icons.speaker_phone_rounded, 'Найти телефон', 'Нажми на Mac — телефон зазвонит даже в беззвучном.'),
        ]),
      ),
    ]);
  }
}

// ── QR scanner ───────────────────────────────────────────────────────────

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('QR-код на Mac'),
      ),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            final v = capture.barcodes.firstOrNull?.rawValue;
            if (v == null || !v.startsWith('androidlink://pair')) return;
            _done = true;
            Navigator.of(context).pop(v);
          },
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 56,
          child: Text(
            'AndroidLink на Mac → «Устройства». Наведи камеру на QR-код.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
      ]),
    );
  }
}
