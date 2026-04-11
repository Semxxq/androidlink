import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/constants/app_constants.dart';

enum BridgeStatus { disconnected, searching, connecting, connected }

class BridgeMessage {
  const BridgeMessage({required this.type, required this.payload, this.id});

  final String type;
  final Map<String, dynamic> payload;
  final String? id;

  factory BridgeMessage.fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return BridgeMessage(
      type:    m['type'] as String,
      payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? {},
      id:      m['id'] as String?,
    );
  }

  String toJson() => jsonEncode({
        'type':    type,
        'payload': payload,
        'id':      id ?? const Uuid().v4(),
      });
}

/// Главный сервис связи Android ↔ Mac по локальной WiFi сети.
///
/// Mac запускает WebSocket сервер на порту 41234.
/// Android находит Mac через mDNS и подключается.
/// Всё работает без интернета — только WiFi.
class BridgeService {
  BridgeService._();
  static final BridgeService instance = BridgeService._();

  final _log     = Logger();
  final _storage = const FlutterSecureStorage();
  final _uuid    = const Uuid();
  final _netInfo = NetworkInfo();

  final _statusStream  = BehaviorSubject<BridgeStatus>.seeded(BridgeStatus.disconnected);
  final _messageStream = StreamController<BridgeMessage>.broadcast();

  Stream<BridgeStatus>  get status        => _statusStream.stream;
  Stream<BridgeMessage> get messages      => _messageStream.stream;
  BridgeStatus          get currentStatus => _statusStream.value;
  bool                  get isConnected   => currentStatus == BridgeStatus.connected;

  WebSocketChannel? _channel;
  HttpServer?       _wsServer;
  Timer?            _heartbeatTimer;
  Timer?            _reconnectTimer;
  String?           _lastMacIp;

  Future<void> init() async {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    if (isMac) {
      await _startServer();
    } else {
      _searchForMac();
    }
  }

  // ══ MAC: сервер ════════════════════════════════════════════════════════

  Future<void> _startServer() async {
    try {
      _wsServer = await HttpServer.bind(InternetAddress.anyIPv4, AL.wsPort);
      _statusStream.add(BridgeStatus.searching);
      _log.i('Server ready on :${AL.wsPort}');

      _wsServer!.transform(WebSocketTransformer()).listen((ws) {
        _log.i('Android connected!');
        _channel = IOWebSocketChannel(ws);
        _statusStream.add(BridgeStatus.connected);
        _startListening();
        _startHeartbeat();
      });
    } catch (e) {
      _log.e('Server start failed', error: e);
    }
  }

  Future<String?> get localIp => _netInfo.getWifiIP();

  // ══ ANDROID: поиск Mac ════════════════════════════════════════════════

  void _searchForMac() {
    _statusStream.add(BridgeStatus.searching);
    _discoverViaMdns();
  }

  Future<void> _discoverViaMdns() async {
    final client = MDnsClient();
    await client.start();

    try {
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(AL.mdnsServiceType),
      ).timeout(const Duration(seconds: 5), onTimeout: (_) {}) ) {
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            client.stop();
            _connectToMac(ip.address.address);
            return;
          }
        }
      }
    } catch (_) {}

    client.stop();
    // mDNS не нашёл — попробуем снова через 5 сек
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _searchForMac);
  }

  Future<void> connectToMacDirectly(String ip) async {
    _lastMacIp = ip;
    _connectToMac(ip);
  }

  Future<void> _connectToMac(String ip) async {
    _statusStream.add(BridgeStatus.connecting);
    _lastMacIp = ip;
    try {
      final uri = Uri.parse('ws://$ip:${AL.wsPort}');
      _channel  = IOWebSocketChannel.connect(uri,
          connectTimeout: const Duration(seconds: 8));
      await _channel!.ready;
      _statusStream.add(BridgeStatus.connected);
      _log.i('Connected to Mac at $ip');
      _startListening();
      _startHeartbeat();
    } catch (e) {
      _log.e('Connection failed: $e');
      _statusStream.add(BridgeStatus.disconnected);
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(
        const Duration(seconds: 5),
        () => _lastMacIp != null
            ? _connectToMac(_lastMacIp!)
            : _searchForMac(),
      );
    }
  }

  // ══ Общее ════════════════════════════════════════════════════════════

  void _startListening() {
    _channel?.stream.listen(
      (raw) {
        if (raw is! String) return;
        try {
          final msg = BridgeMessage.fromJson(raw);
          if (msg.type == AL.typePong) return;
          _messageStream.add(msg);
        } catch (e) {
          _log.e('Parse error', error: e);
        }
      },
      onDone:  _onDisconnected,
      onError: (_) => _onDisconnected(),
    );
  }

  void send(BridgeMessage message) {
    if (!isConnected) return;
    _channel?.sink.add(message.toJson());
  }

  void sendRaw(Map<String, dynamic> payload, String type) {
    send(BridgeMessage(type: type, payload: payload, id: _uuid.v4()));
  }

  void _onDisconnected() {
    _log.w('Disconnected');
    _statusStream.add(BridgeStatus.disconnected);
    _heartbeatTimer?.cancel();

    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    if (!isMac) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3),
          () => _lastMacIp != null ? _connectToMac(_lastMacIp!) : _searchForMac());
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(AL.heartbeat, (_) {
      sendRaw({}, AL.typePing);
    });
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _statusStream.add(BridgeStatus.disconnected);
  }
}
