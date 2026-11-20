import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import 'link_crypto.dart';

enum BridgeStatus { disconnected, searching, connecting, connected }

class BridgeMessage {
  const BridgeMessage({
    required this.type,
    required this.payload,
    this.id,
    this.deviceId,
  });

  final String type;
  final Map<String, dynamic> payload;
  final String? id;

  /// Mac side: which phone sent it.
  final String? deviceId;

  factory BridgeMessage.fromMap(Map<String, dynamic> m, {String? deviceId}) =>
      BridgeMessage(
        type: m['type'] as String? ?? '',
        payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        id: m['id'] as String?,
        deviceId: deviceId,
      );

  factory BridgeMessage.fromJson(String raw, {String? deviceId}) =>
      BridgeMessage.fromMap(jsonDecode(raw) as Map<String, dynamic>,
          deviceId: deviceId);
}

/// A phone as seen by the Mac.
class PeerInfo {
  PeerInfo({required this.id, required this.name});
  final String id;
  String name;
  int battery = -1;
  bool charging = false;
  String? model;
  String? android;
}

/// Facade used by the UI on both platforms.
///
/// Mac: encrypted WebSocket server + UDP beacon + QR pairing ([_MacHost]).
/// Android: proxy to the native foreground `LinkService` ([_PhoneLink]),
/// so the link survives the UI being closed.
class BridgeService {
  BridgeService._();
  static final BridgeService instance = BridgeService._();

  final _log = Logger();
  final _uuid = const Uuid();

  final _status = BehaviorSubject<BridgeStatus>.seeded(BridgeStatus.disconnected);
  final _messages = StreamController<BridgeMessage>.broadcast();
  final _devices = BehaviorSubject<List<PeerInfo>>.seeded(const []);
  final _qr = BehaviorSubject<String?>.seeded(null);
  final _issue = BehaviorSubject<String?>.seeded(null);
  final _peerName = BehaviorSubject<String?>.seeded(null);

  Stream<BridgeStatus> get status => _status.stream;
  Stream<BridgeMessage> get messages => _messages.stream;
  Stream<List<PeerInfo>> get devices => _devices.stream;
  Stream<int> get deviceCount => _devices.stream.map((d) => d.length);
  List<PeerInfo> get currentDevices => _devices.value;
  BridgeStatus get currentStatus => _status.value;
  bool get isConnected => currentStatus == BridgeStatus.connected;

  /// Mac: pairing QR (rotates after every successful pairing / IP change).
  Stream<String?> get qrStream => _qr.stream;
  String? get qrData => _qr.value;
  String? get localIp => _mac?._ips.firstOrNull;

  /// Android: 'unpaired' | 'unauthorized' | null.
  Stream<String?> get pairingIssue => _issue.stream;

  /// Android: name of the paired Mac.
  Stream<String?> get peerName => _peerName.stream;

  _MacHost? _mac;
  _PhoneLink? _phone;

  Future<void> init() async {
    if (Platform.isMacOS) {
      _mac = _MacHost(this);
      await _mac!.start();
    } else if (Platform.isAndroid) {
      _phone = _PhoneLink(this);
      await _phone!.start();
    }
  }

  void send(BridgeMessage m, {String? deviceId}) {
    if (_mac != null) {
      _mac!.send(m.type, m.payload, m.id ?? _uuid.v4(), deviceId: deviceId ?? m.deviceId);
    } else {
      _phone?.send(m.type, m.payload);
    }
  }

  void sendRaw(Map<String, dynamic> payload, String type, {String? deviceId}) =>
      send(BridgeMessage(type: type, payload: payload, id: _uuid.v4()),
          deviceId: deviceId);

  // ── Android ──
  Future<bool> connectViaQr(String qr) async => await _phone?.pair(qr) ?? false;
  Future<bool> connectToMacDirectly(String ip) async => await _phone?.connectIp(ip) ?? false;
  Future<void> unpair() async => _phone?.unpair();

  // ── Mac ──
  List<PeerInfo> get pairedDevices => _mac?.paired ?? const [];
  Future<void> forgetDevice(String id) async => _mac?.forget(id);

  void disconnect() => _mac?.stop();
}

// ═══════════════════════════════ MAC ═══════════════════════════════════

class _Paired {
  _Paired(this.id, this.name, this.keyB64);
  final String id;
  String name;
  final String keyB64;
  SecretKey get key => SecretKey(base64Decode(keyB64));
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'k': keyB64};
}

class _Peer {
  _Peer(this.ws, this.info, this.key, this.phoneSid, this.macSid);
  final WebSocket ws;
  final PeerInfo info;
  final SecretKey key;
  final String phoneSid;
  final String macSid;

  // Crypto is async; chain keeps frame order.
  Future<void> _inChain = Future.value();
  Future<void> _outChain = Future.value();
  void inbound(Future<void> Function() f) =>
      _inChain = _inChain.then((_) => f()).catchError((Object _) {});
  void outbound(Future<void> Function() f) =>
      _outChain = _outChain.then((_) => f()).catchError((Object _) {});
}

class _MacHost {
  _MacHost(this.b);
  final BridgeService b;
  Logger get _log => b._log;

  static const _beaconTag = 'ANDROIDLINK2';

  late File _storeFile;
  String _macId = '';
  final Map<String, _Paired> _pairedMap = {};
  final List<_Peer> _peers = [];

  List<String> _ips = [];
  int _port = AL.wsPort;
  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _beaconTimer;
  Timer? _ipTimer;

  // Pending pairing shown in the QR. Single use.
  late List<int> _pendingKey;
  late String _pendingId;

  String get _macName {
    final h = Platform.localHostname.replaceAll(RegExp(r'\.local$'), '');
    return h.replaceAll('-', ' ');
  }

  List<PeerInfo> get paired =>
      _pairedMap.values.map((p) => PeerInfo(id: p.id, name: p.name)).toList();

  Future<void> start() async {
    await _load();
    _rotatePairing();
    await _bindServer();
    await _refreshIps();
    _ipTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshIps());
    await _startBeacon();
  }

  void stop() {
    _beaconTimer?.cancel();
    _ipTimer?.cancel();
    _udp?.close();
    for (final p in List.of(_peers)) {
      p.ws.close(1001, 'shutdown');
    }
    _peers.clear();
    _server?.close(force: true);
    b._status.add(BridgeStatus.disconnected);
  }

  // ── storage ──

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _storeFile = File('${dir.path}/pairing.json');
    try {
      final m = jsonDecode(await _storeFile.readAsString()) as Map<String, dynamic>;
      _macId = m['macId'] as String? ?? '';
      for (final d in (m['devices'] as List? ?? const [])) {
        final dm = (d as Map).cast<String, dynamic>();
        _pairedMap[dm['id'] as String] =
            _Paired(dm['id'] as String, dm['name'] as String? ?? 'Android', dm['k'] as String);
      }
    } catch (_) {/* first run */}
    if (_macId.isEmpty) {
      _macId = LinkCrypto.randomId();
      await _save();
    }
  }

  Future<void> _save() async {
    final tmp = File('${_storeFile.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'macId': _macId,
      'devices': _pairedMap.values.map((p) => p.toJson()).toList(),
    }));
    await tmp.rename(_storeFile.path);
  }

  Future<void> forget(String id) async {
    _pairedMap.remove(id);
    await _save();
    for (final p in _peers.where((p) => p.info.id == id).toList()) {
      p.ws.close(4401, 'forgotten');
    }
  }

  // ── pairing QR ──

  void _rotatePairing() {
    _pendingKey = LinkCrypto.randomBytes(32);
    _pendingId = LinkCrypto.randomId();
    _publishQr();
  }

  void _publishQr() {
    if (_ips.isEmpty) {
      b._qr.add(null);
      return;
    }
    final uri = Uri(scheme: 'androidlink', host: 'pair', queryParameters: {
      'h': _ips.join(','),
      'p': '$_port',
      'k': base64Url.encode(_pendingKey).replaceAll('=', ''),
      'i': _pendingId,
      'm': _macId,
      'n': _macName,
    });
    b._qr.add(uri.toString());
  }

  Future<void> _refreshIps() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      int rank(NetworkInterface i) => i.name.startsWith('en') ? 0 : (i.name.startsWith('utun') ? 2 : 1);
      ifs.sort((a, c) => rank(a).compareTo(rank(c)));
      final ips = <String>[
        for (final i in ifs)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a.address,
      ];
      if (ips.join(',') != _ips.join(',')) {
        _ips = ips;
        _log.i('Mac IPs: $_ips');
        _publishQr();
      }
    } catch (e) {
      _log.w('IP refresh failed: $e');
    }
  }

  // ── server ──

  Future<void> _bindServer() async {
    for (var p = AL.wsPort; p < AL.wsPort + 6; p++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        _port = p;
        break;
      } catch (_) {}
    }
    if (_server == null) {
      _log.e('No free port for WS server');
      return;
    }
    b._status.add(BridgeStatus.searching);
    _log.i('WS server on :$_port');
    _server!.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      try {
        _onSocket(await WebSocketTransformer.upgrade(req));
      } catch (_) {}
    });
  }

  void _onSocket(WebSocket ws) {
    ws.pingInterval = const Duration(seconds: 10);
    _Peer? peer;
    final helloTimer = Timer(const Duration(seconds: 10), () {
      if (peer == null) ws.close(4408, 'hello timeout');
    });
    void done() {
      helloTimer.cancel();
      if (peer != null) _removePeer(peer!);
    }

    ws.listen(
      (raw) {
        if (raw is! String) return;
        final p = peer;
        if (p == null) {
          peer = _handshake(ws, raw);
          if (peer != null) helloTimer.cancel();
          return;
        }
        p.inbound(() => _onFrame(p, raw));
      },
      onDone: done,
      onError: (_) => done(),
      cancelOnError: true,
    );
  }

  _Peer? _handshake(WebSocket ws, String raw) {
    Map<String, dynamic> h;
    try {
      h = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      ws.close(4400, 'bad hello');
      return null;
    }
    final deviceId = h['device'] as String? ?? '';
    final phoneSid = h['s'] as String? ?? '';
    final name = h['name'] as String? ?? 'Android';
    final pairId = h['pair'] as String?;
    if (deviceId.isEmpty || phoneSid.isEmpty) {
      ws.close(4400, 'bad hello');
      return null;
    }

    _Paired? rec;
    if (pairId != null && pairId == _pendingId) {
      rec = _Paired(deviceId, name, base64Encode(_pendingKey));
      _pairedMap[deviceId] = rec;
      _save();
      _rotatePairing();
      _log.i('Paired new device $name');
    } else {
      rec = _pairedMap[deviceId];
    }
    if (rec == null) {
      ws.close(4401, 'unpaired');
      return null;
    }

    // One live socket per phone.
    for (final old in _peers.where((p) => p.info.id == deviceId).toList()) {
      _peers.remove(old);
      old.ws.close(1000, 'replaced');
    }

    final peer = _Peer(ws, PeerInfo(id: deviceId, name: rec.name), rec.key,
        phoneSid, LinkCrypto.randomId());
    _peers.add(peer);
    _emitPeers();
    _sendTo(peer, 'welcome', {'mac': _macId, 'name': _macName, 's': peer.macSid},
        LinkCrypto.randomId());
    _log.i('Android connected: ${peer.info.name}. Total: ${_peers.length}');
    return peer;
  }

  Future<void> _onFrame(_Peer p, String raw) async {
    final plain = await LinkCrypto.open(p.key, raw);
    if (plain == null) {
      await p.ws.close(4403, 'bad frame');
      return;
    }
    final env = jsonDecode(plain) as Map<String, dynamic>;
    if (env['s'] != p.macSid) return;
    final msg = BridgeMessage.fromMap(env, deviceId: p.info.id);

    if (msg.type == 'device_info' || msg.type == 'battery') {
      final pl = msg.payload;
      if (pl['name'] is String && pl['name'] != p.info.name) {
        p.info.name = pl['name'] as String;
        _pairedMap[p.info.id]?.name = p.info.name;
        _save();
      }
      p.info.model = pl['model'] as String? ?? p.info.model;
      p.info.android = pl['android'] as String? ?? p.info.android;
      final lvl = pl['battery'] ?? pl['level'];
      if (lvl is int) p.info.battery = lvl;
      if (pl['charging'] is bool) p.info.charging = pl['charging'] as bool;
      _emitPeers();
    }
    b._messages.add(msg);
  }

  void _removePeer(_Peer p) {
    if (!_peers.remove(p)) return;
    _emitPeers();
    _log.w('Android disconnected: ${p.info.name}. Remaining: ${_peers.length}');
  }

  void _emitPeers() {
    b._devices.add(_peers.map((p) => p.info).toList());
    b._status.add(_peers.isEmpty ? BridgeStatus.searching : BridgeStatus.connected);
  }

  void send(String type, Map<String, dynamic> payload, String id, {String? deviceId}) {
    for (final p in _peers) {
      if (deviceId == null || p.info.id == deviceId) _sendTo(p, type, payload, id);
    }
  }

  void _sendTo(_Peer p, String type, Map<String, dynamic> payload, String id) {
    p.outbound(() async {
      final frame = await LinkCrypto.seal(
          p.key, jsonEncode({'type': type, 'payload': payload, 'id': id, 's': p.phoneSid}));
      p.ws.add(frame);
    });
  }

  // ── discovery beacon ──

  Future<void> _startBeacon() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udp!.broadcastEnabled = true;
    } catch (e) {
      _log.e('UDP beacon failed: $e');
      return;
    }
    _beaconTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final data = utf8.encode('$_beaconTag|$_macId|$_port');
      final targets = {
        '255.255.255.255',
        for (final ip in _ips)
          if (ip.split('.').length == 4) '${ip.substring(0, ip.lastIndexOf('.'))}.255',
      };
      for (final t in targets) {
        try {
          _udp?.send(data, InternetAddress(t), AL.udpPort);
        } catch (_) {}
      }
    });
  }
}

// ═════════════════════════════ ANDROID ═════════════════════════════════

class _PhoneLink {
  _PhoneLink(this.b);
  final BridgeService b;

  static const _methods = MethodChannel('com.androidlink/methods');
  static const _events = EventChannel('com.androidlink/link');

  Future<void> start() async {
    _events.receiveBroadcastStream().listen((e) {
      final m = (e as Map).cast<String, dynamic>();
      switch (m['kind']) {
        case 'status':
          _applyStatus(m['data'] as String);
        case 'message':
          try {
            b._messages.add(BridgeMessage.fromJson(m['data'] as String));
          } catch (_) {}
      }
    });
    await _refreshState();
  }

  Future<void> _refreshState() async {
    try {
      final s = (await _methods.invokeMethod<Map>('state'))?.cast<String, dynamic>();
      if (s == null) return;
      b._peerName.add(s['macName'] as String?);
      _applyStatus(s['status'] as String? ?? 'unpaired');
    } catch (_) {}
  }

  void _applyStatus(String s) {
    b._issue.add(s == 'unpaired' || s == 'unauthorized' ? s : null);
    b._status.add(switch (s) {
      'connected' => BridgeStatus.connected,
      'connecting' => BridgeStatus.connecting,
      'searching' => BridgeStatus.searching,
      _ => BridgeStatus.disconnected,
    });
    if (s == 'connected') {
      _methods.invokeMethod<Map>('state').then((st) {
        b._peerName.add(st?['macName'] as String?);
      }).catchError((Object _) {});
    }
  }

  void send(String type, Map<String, dynamic> payload) {
    _methods.invokeMethod('send', {'type': type, 'payload': jsonEncode(payload)})
        .catchError((Object _) {});
  }

  Future<bool> pair(String qr) async {
    final ok = await _methods.invokeMethod<bool>('pair', {'qr': qr}) ?? false;
    await _refreshState();
    return ok;
  }

  Future<bool> connectIp(String ip) async =>
      await _methods.invokeMethod<bool>('connectIp', {'ip': ip}) ?? false;

  Future<void> unpair() async {
    await _methods.invokeMethod('unpair');
    await _refreshState();
  }
}
