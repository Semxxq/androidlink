import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../features/bridge/services/bridge_service.dart';
import '../features/bridge/services/file_transfer.dart';
import 'models.dart';
import 'notifier.dart';

/// Single source of truth for the Mac UI. Lives for the whole app run, so
/// nothing is lost when screens rebuild or the phone reconnects; history is
/// persisted to Application Support.
class MacStore extends ChangeNotifier {
  MacStore._();
  static final MacStore instance = MacStore._();

  final _b = BridgeService.instance;
  final _uuid = const Uuid();

  // ── state ──
  final Map<String, SmsThread> _threads = {};
  final List<CallEntry> calls = [];
  final List<PhoneNotif> notifications = [];
  final List<ClipEntry> clipboard = [];
  final Map<String, String> _names = {};
  List<Contact> contacts = [];
  List<PeerInfo> devices = [];
  LiveCall? liveCall;
  String? selectedDeviceId;
  bool syncing = false;
  String? toast;

  // settings
  bool autoClipboard = true;
  bool banners = true;

  late File _historyFile;
  late File _settingsFile;
  Timer? _saveTimer;
  Timer? _clipTimer;
  String? _lastClip;
  final List<Contact> _contactsBuf = [];
  final Set<String> _syncedDevices = {};

  PeerInfo? get device {
    if (devices.isEmpty) return null;
    return devices.firstWhere((d) => d.id == selectedDeviceId, orElse: () => devices.first);
  }

  bool get connected => device != null;

  List<SmsThread> get threads {
    final l = _threads.values.where((t) => t.messages.isNotEmpty).toList()
      ..sort((a, b) => b.last!.ts.compareTo(a.last!.ts));
    return l;
  }

  int get unreadCount => _threads.values.fold(0, (s, t) => s + t.unread);

  SmsThread? thread(String key) => _threads[key];

  String displayName(String address) => address.contains(',')
      ? address.split(',').map((a) => _names[normalizeNumber(a)] ?? a.trim()).join(', ')
      : _names[normalizeNumber(address)] ?? address;
  bool hasName(String address) => _names.containsKey(normalizeNumber(address));

  // ── lifecycle ──

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _historyFile = File('${dir.path}/history.json');
    _settingsFile = File('${dir.path}/settings.json');
    await _load();

    MacNotifier.instance.enabled = banners;
    MacNotifier.instance.onResponse = _onBannerResponse;
    FileTransferHub.instance.start();
    FileTransferHub.instance.received.listen((t) {
      MacNotifier.instance.show(
        key: 'file:${t.fid}',
        title: 'Файл с телефона',
        body: t.name,
        category: MacNotifier.catFile,
        payload: 'file|${t.path}',
      );
    });

    _b.messages.listen(_onMessage);
    _b.devices.listen((d) {
      devices = d;
      _syncedDevices.removeWhere((id) => !d.any((x) => x.id == id));
      notifyListeners();
    });

    _lastClip = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    _clipTimer = Timer.periodic(const Duration(milliseconds: 800), (_) => _pollClipboard());
  }

  Future<void> _load() async {
    try {
      final s = jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>;
      autoClipboard = s['autoClipboard'] as bool? ?? true;
      banners = s['banners'] as bool? ?? true;
      selectedDeviceId = s['device'] as String?;
    } catch (_) {}
    try {
      final h = jsonDecode(await _historyFile.readAsString()) as Map<String, dynamic>;
      for (final m in (h['sms'] as List? ?? const [])) {
        _addSms(SmsMsg.fromJson((m as Map).cast()), sort: false);
      }
      for (final t in _threads.values) {
        t.messages.sort((a, b) => a.ts.compareTo(b.ts));
      }
      calls.addAll((h['calls'] as List? ?? const []).map((c) => CallEntry.fromJson((c as Map).cast())));
      contacts = (h['contacts'] as List? ?? const []).map((c) => Contact.fromJson((c as Map).cast())).toList();
      _rebuildNames();
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    final sms = <Map<String, dynamic>>[];
    for (final t in _threads.values) {
      for (final m in t.messages.length > 400 ? t.messages.sublist(t.messages.length - 400) : t.messages) {
        if (!m.isLocal) sms.add(m.toJson());
      }
    }
    try {
      final tmp = File('${_historyFile.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'sms': sms,
        'calls': calls.take(500).map((c) => c.toJson()).toList(),
        'contacts': contacts.map((c) => c.toJson()).toList(),
      }));
      await tmp.rename(_historyFile.path);
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _settingsFile.writeAsString(jsonEncode({
        'autoClipboard': autoClipboard,
        'banners': banners,
        'device': selectedDeviceId,
      }));
    } catch (_) {}
  }

  // ── incoming ──

  void _onMessage(BridgeMessage m) {
    final p = m.payload;
    switch (m.type) {
      case AL.typeDeviceInfo:
        if (m.deviceId != null && _syncedDevices.add(m.deviceId!)) _requestSync(m.deviceId!);
      case AL.typeSms:
        final msg = SmsMsg.fromJson(p);
        final isNew = _addSms(msg);
        _learnNames(p);
        if (isNew && msg.incoming) _bannerSms(msg);
        _scheduleSave();
      case AL.typeSmsBatch:
        for (final i in (p['items'] as List? ?? const [])) {
          final j = (i as Map).cast<String, dynamic>();
          _addSms(SmsMsg.fromJson(j), sort: false);
          _learnNames(j);
        }
        for (final t in _threads.values) {
          t.messages.sort((a, b) => a.ts.compareTo(b.ts));
        }
        if (p['done'] == true) syncing = false;
        _scheduleSave();
      case AL.typeSmsStatus:
        final ref = p['ref'] as String?;
        for (final t in _threads.values) {
          for (final x in t.messages) {
            if (x.id == ref) x.status = p['status'] as String? ?? x.status;
          }
        }
        if (p['status'] == 'failed') _toast('Не удалось отправить SMS');
      case AL.typeCall:
        _onLiveCall(p, m.deviceId);
      case AL.typeCallBatch:
        final items = (p['items'] as List? ?? const []).map((c) => CallEntry.fromJson((c as Map).cast())).toList();
        if (items.isNotEmpty) {
          calls
            ..clear()
            ..addAll(items);
          for (final c in items) {
            if (c.name != null) _names.putIfAbsent(normalizeNumber(c.address), () => c.name!);
          }
          _scheduleSave();
        }
      case AL.typeContactsBatch:
        _contactsBuf.addAll((p['items'] as List? ?? const []).map((c) => Contact.fromJson((c as Map).cast())));
        if (p['done'] == true) {
          if (_contactsBuf.isNotEmpty) contacts = List.of(_contactsBuf);
          _contactsBuf.clear();
          _rebuildNames();
          _scheduleSave();
        }
      case AL.typeNotif:
        final n = PhoneNotif.fromJson(p);
        notifications.removeWhere((x) => x.key == n.key);
        notifications.insert(0, n);
        if (notifications.length > 200) notifications.removeLast();
        MacNotifier.instance.show(
          key: 'n:${n.key}',
          title: n.title.isEmpty ? n.app : n.title,
          subtitle: n.title.isEmpty ? null : n.app,
          body: n.body,
          category: n.canReply ? MacNotifier.catReply : null,
          payload: 'notif|${n.key}',
          thread: n.pkg,
        );
      case AL.typeNotifRemoved:
        final key = p['key'] as String? ?? '';
        notifications.removeWhere((x) => x.key == key);
        MacNotifier.instance.cancel('n:$key');
      case AL.typeClipboard:
        final text = p['text'] as String? ?? '';
        if (text.isEmpty) break;
        _lastClip = text;
        Clipboard.setData(ClipboardData(text: text));
        _addClip(text, true);
        if (p['shared'] == true) _toast('Текст с телефона скопирован');
      case AL.typeClipImage:
        final b64 = p['image'] as String? ?? '';
        if (b64.isEmpty) break;
        final bytes = base64Decode(b64);
        _setClipImage(bytes);
        _addClip('Изображение', true, image: bytes);
        notifyListeners();
      case AL.typeCallResult:
        if (p['ok'] != true) {
          _toast(p['action'] == 'dial'
              ? 'Телефон не смог позвонить — проверь разрешение «Звонки»'
              : 'Телефон не выполнил действие со звонком');
        }
      case AL.typeNotifReplyResult:
        if (p['ok'] != true) _toast('Не удалось ответить на уведомление');
      default:
        return;
    }
    notifyListeners();
  }

  void _requestSync(String deviceId) {
    syncing = true;
    _b.sendRaw({'limit': 2000}, AL.typeSmsSync, deviceId: deviceId);
    _b.sendRaw({'limit': 300}, AL.typeCallsSync, deviceId: deviceId);
    _b.sendRaw({}, AL.typeContactsSync, deviceId: deviceId);
  }

  void resync() {
    final d = device;
    if (d != null) _requestSync(d.id);
    notifyListeners();
  }

  /// Returns true if the message is new.
  void _learnNames(Map<String, dynamic> j) {
    final addr = j['address'] as String? ?? '';
    if (j['name'] is String && !addr.contains(',')) _names[normalizeNumber(addr)] = j['name'] as String;
    final ns = j['names'];
    if (ns is Map) {
      ns.forEach((k, v) {
        if (v is String) _names[normalizeNumber(k as String)] = v;
      });
    }
  }

  bool _addSms(SmsMsg msg, {bool sort = true}) {
    final key = threadKey(msg.address);
    final t = _threads.putIfAbsent(key, () => SmsThread(key, msg.address));
    final i = t.messages.indexWhere((x) => x.id == msg.id);
    if (i >= 0) {
      final old = t.messages[i];
      msg.read = old.read || msg.read;
      t.messages[i] = msg;
      return false;
    }
    if (!msg.incoming) {
      // Our own reply comes back from the phone's SMS database: swap the local bubble.
      final local = t.messages.indexWhere((x) =>
          x.isLocal && x.body == msg.body && (msg.ts - x.ts).abs() < 10 * 60 * 1000);
      if (local >= 0) {
        t.messages[local] = msg;
        return false;
      }
    }
    t.messages.add(msg);
    if (sort && t.messages.length > 1 && t.messages[t.messages.length - 2].ts > msg.ts) {
      t.messages.sort((a, b) => a.ts.compareTo(b.ts));
    }
    return true;
  }

  void _rebuildNames() {
    for (final c in contacts) {
      for (final n in c.numbers) {
        _names[normalizeNumber(n)] = c.name;
      }
    }
  }

  void _onLiveCall(Map<String, dynamic> p, String? deviceId) {
    final id = p['id'] as String? ?? '';
    final state = p['state'] as String? ?? '';
    final address = p['address'] as String? ?? '';
    final name = (p['name'] as String?) ?? (hasName(address) ? displayName(address) : null);
    if (p['name'] is String) _names[normalizeNumber(address)] = p['name'] as String;
    final who = name ?? address;
    switch (state) {
      case 'ringing':
        liveCall = LiveCall(id: id, address: address, state: state, incoming: true, name: name);
        MacNotifier.instance.show(
          key: 'call:$id',
          title: who,
          body: 'Входящий звонок',
          category: MacNotifier.catCall,
          payload: 'call|$id',
        );
      case 'dialing':
        liveCall = LiveCall(id: id, address: address, state: state, incoming: false, name: name);
      case 'answered':
        liveCall?.state = 'answered';
        liveCall?.since = DateTime.now();
        MacNotifier.instance.cancel('call:$id');
      case 'ended':
        liveCall = null;
        MacNotifier.instance.cancel('call:$id');
        if (p['type'] == 'missed') {
          MacNotifier.instance.show(
            key: 'missed:$id',
            title: who,
            body: 'Пропущенный звонок',
            payload: 'missed|$address',
          );
        }
        Future.delayed(const Duration(seconds: 2), () {
          _b.sendRaw({'limit': 300}, AL.typeCallsSync, deviceId: deviceId);
        });
    }
  }

  void _bannerSms(SmsMsg m) {
    MacNotifier.instance.show(
      key: 'sms:${m.id}',
      title: displayName(m.address),
      body: [
        if (m.sender != null && m.address.contains(',')) '${displayName(m.sender!)}:',
        m.body.isEmpty && m.image != null ? '📷 Фото' : m.body,
      ].join(' '),
      category: MacNotifier.catSms,
      payload: 'sms|${m.address}',
      thread: threadKey(m.address),
    );
  }

  void _onBannerResponse(String kind, String id, String? action, String? input) {
    switch (kind) {
      case 'sms':
        if (action == 'reply' && (input ?? '').trim().isNotEmpty) {
          sendSms(id, input!.trim());
        } else {
          openThreadRequest.value = threadKey(id);
        }
      case 'call':
        if (action == 'answer') callAction('answer');
        if (action == 'decline') callAction('decline');
      case 'missed':
        openTabRequest.value = 1;
      case 'notif':
        if (action == 'reply' && (input ?? '').trim().isNotEmpty) replyNotification(id, input!.trim());
        if (action == 'dismiss') dismissNotification(id);
      case 'file':
        if (id.isNotEmpty) revealInFinder(id);
    }
  }

  // UI navigation requests coming from banners.
  final openThreadRequest = ValueNotifier<String?>(null);
  final openTabRequest = ValueNotifier<int?>(null);

  void _toast(String s) {
    toast = s;
    notifyListeners();
    Future.delayed(const Duration(seconds: 4), () {
      if (toast == s) {
        toast = null;
        notifyListeners();
      }
    });
  }

  // ── clipboard ──

  static const _native = MethodChannel('androidlink/tray');
  int _clipCount = -1;
  static const _maxImage = 8 * 1024 * 1024;

  Future<void> _setClipImage(Uint8List bytes) async {
    try {
      _clipCount = await _native.invokeMethod<int>('setClipImage', bytes) ?? _clipCount;
    } catch (_) {}
  }

  Future<Uint8List?> _readClipImage() async {
    try {
      return await _native.invokeMethod<Uint8List>('clipImage');
    } catch (_) {
      return null;
    }
  }

  void _sendImage(Uint8List img) => _b.sendRaw({'image': base64Encode(img)}, AL.typeClipImage, deviceId: device!.id);

  Future<void> _pollClipboard() async {
    try {
      final count = await _native.invokeMethod<int>('clipCount').catchError((_) => -2);
      if (count != null && count >= 0) {
        if (count == _clipCount) return;
        _clipCount = count;
      }
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text == null || text.isEmpty) {
        if (count == null || count < 0) return;
        final img = await _readClipImage();
        if (img == null || img.length > _maxImage) return;
        _addClip('Изображение', false, image: img);
        if (autoClipboard && connected) _sendImage(img);
        notifyListeners();
        return;
      }
      if (text == _lastClip) return;
      _lastClip = text;
      _addClip(text, false);
      if (autoClipboard && connected) {
        _b.sendRaw({'text': text}, AL.typeClipboard, deviceId: device!.id);
      }
      notifyListeners();
    } catch (_) {}
  }

  void _addClip(String text, bool fromPhone, {Uint8List? image}) {
    if (image == null) clipboard.removeWhere((c) => c.image == null && c.text == text);
    clipboard.insert(0, ClipEntry(text, fromPhone, image: image));
    if (clipboard.length > 50) clipboard.removeLast();
  }

  Future<void> pushClipboard() async {
    if (!connected) return;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) {
      final img = await _readClipImage();
      if (img == null || img.length > _maxImage) return;
      _sendImage(img);
      _toast('Изображение отправлено на телефон');
      return;
    }
    _b.sendRaw({'text': text}, AL.typeClipboard, deviceId: device!.id);
    _toast('Буфер отправлен на телефон');
  }

  Future<void> copyEntry(ClipEntry c) async {
    if (c.image == null) return copy(c.text);
    await _setClipImage(c.image!);
    if (autoClipboard && connected) _sendImage(c.image!);
  }

  Future<void> copy(String text) async {
    _lastClip = text;
    await Clipboard.setData(ClipboardData(text: text));
    if (autoClipboard && connected) _b.sendRaw({'text': text}, AL.typeClipboard, deviceId: device!.id);
  }

  // ── actions ──

  void sendSms(String address, String body) {
    if (!connected || body.trim().isEmpty) return;
    final id = 'local:${_uuid.v4()}';
    _addSms(SmsMsg(
        id: id, address: address, body: body, ts: DateTime.now().millisecondsSinceEpoch,
        incoming: false, status: 'sending'));
    _b.sendRaw({'id': id, 'address': address, 'body': body}, AL.typeSmsReply, deviceId: device!.id);
    notifyListeners();
  }

  /// Starts a new conversation; returns the thread key.
  String newThread(String address) {
    final key = threadKey(address);
    _threads.putIfAbsent(key, () => SmsThread(key, address));
    notifyListeners();
    return key;
  }

  void markRead(String key) {
    final t = _threads[key];
    if (t == null || t.unread == 0) return;
    for (final m in t.messages) {
      m.read = true;
    }
    _scheduleSave();
    notifyListeners();
  }

  void callAction(String action) {
    if (!connected) return;
    _b.sendRaw({'action': action}, AL.typeCallAction, deviceId: device!.id);
  }

  void dial(String number) {
    if (!connected || number.trim().isEmpty) return;
    _b.sendRaw({'number': number.trim()}, AL.typeCallDial, deviceId: device!.id);
    _toast('Звоним с телефона: ${displayName(number)}');
  }

  bool ringing = false;
  Timer? _ringTimer;

  void ring() {
    if (!connected) return;
    if (ringing) return stopRing();
    _b.sendRaw({'seconds': 30}, AL.typeRing, deviceId: device!.id);
    ringing = true;
    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 30), () {
      ringing = false;
      notifyListeners();
    });
    _toast('Телефон звонит 30 секунд');
    notifyListeners();
  }

  void stopRing() {
    _ringTimer?.cancel();
    ringing = false;
    if (connected) _b.sendRaw({}, AL.typeRingStop, deviceId: device!.id);
    notifyListeners();
  }

  void dismissNotification(String key) {
    notifications.removeWhere((n) => n.key == key);
    MacNotifier.instance.cancel('n:$key');
    if (connected) _b.sendRaw({'key': key}, AL.typeNotifDismiss, deviceId: device!.id);
    notifyListeners();
  }

  void clearNotifications() {
    for (final n in List.of(notifications)) {
      dismissNotification(n.key);
    }
  }

  void replyNotification(String key, String text) {
    if (!connected) return;
    _b.sendRaw({'key': key, 'text': text}, AL.typeNotifReply, deviceId: device!.id);
  }

  Future<void> sendFiles(List<File> files) async {
    final d = device;
    if (d == null) return;
    for (final f in files) {
      if (await FileSystemEntity.isDirectory(f.path)) continue;
      unawaited(FileTransferHub.instance.sendFile(f, deviceId: d.id));
    }
  }

  // Sandbox blocks spawning `open`; NSWorkspace via the native channel works.
  Future<void> revealInFinder(String path) async {
    try {
      await _native.invokeMethod('reveal', path);
    } catch (_) {}
  }

  Future<void> openFile(String path) async {
    try {
      final ok = await _native.invokeMethod<bool>('openFile', path) ?? false;
      if (!ok) _toast('Файл не найден — возможно, его переместили');
    } catch (_) {}
  }

  void selectDevice(String id) {
    selectedDeviceId = id;
    _saveSettings();
    notifyListeners();
  }

  void setAutoClipboard(bool v) {
    autoClipboard = v;
    _saveSettings();
    notifyListeners();
  }

  void setBanners(bool v) {
    banners = v;
    MacNotifier.instance.enabled = v;
    _saveSettings();
    notifyListeners();
  }

  Future<void> forgetDevice(String id) async {
    await _b.forgetDevice(id);
    notifyListeners();
  }

  @override
  void dispose() {
    _clipTimer?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }
}
