import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
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

/// Mac запускает WebSocket-сервер и рассылает UDP-beacon каждые 2 сек.
/// Android слушает UDP, находит IP мака, подключается по WebSocket.
/// Несколько Android-устройств могут подключаться одновременно.
class BridgeService {
  BridgeService._();
  static final BridgeService instance = BridgeService._();

  final _log     = Logger();
  final _uuid    = const Uuid();
  final _netInfo = NetworkInfo();

  final _statusStream          = BehaviorSubject<BridgeStatus>.seeded(BridgeStatus.disconnected);
  final _messageStream         = StreamController<BridgeMessage>.broadcast();
  final _connectedDevicesCount = BehaviorSubject<int>.seeded(0);

  Stream<BridgeStatus>  get status           => _statusStream.stream;
  Stream<BridgeMessage> get messages         => _messageStream.stream;
  Stream<int>           get deviceCount      => _connectedDevicesCount.stream;
  BridgeStatus          get currentStatus    => _statusStream.value;
  bool                  get isConnected      => currentStatus == BridgeStatus.connected;
  String?               get localIp          => _localIp;

  /// QR-данные для отображения на Маке: androidlink://IP:PORT
  String? get qrData =>
      _localIp != null ? 'androidlink://$_localIp:${AL.wsPort}' : null;

  // Mac: список подключённых клиентов
  final List<WebSocket> _clients = [];
  HttpServer?           _wsServer;
  RawDatagramSocket?    _udpBroadcastSocket;
  Timer?                _broadcastTimer;

  // Android: одно соединение с Маком
  WebSocketChannel? _channel;
  Timer?            _heartbeatTimer;
  Timer?            _reconnectTimer;
  RawDatagramSocket? _udpListenSocket;
  String?           _lastMacIp;
  String?           _localIp;

  Future<void> init() async {
    _localIp = await _netInfo.getWifiIP();
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    if (isMac) {
      await _startServer();
      _startUdpBroadcast();
    } else {
      _listenForMacUdp();
    }
  }

  // ══ MAC: WebSocket сервер ══════════════════════════════════════════════

  Future<void> _startServer() async {
    try {
      _wsServer = await HttpServer.bind(InternetAddress.anyIPv4, AL.wsPort);
      _statusStream.add(BridgeStatus.searching);
      _log.i('WS server ready on :${AL.wsPort}');

      _wsServer!.transform(WebSocketTransformer()).listen((ws) {
        _clients.add(ws);
        _connectedDevicesCount.add(_clients.length);
        _statusStream.add(BridgeStatus.connected);
        _log.i('Android connected. Total: ${_clients.length}');

        ws.listen(
          (raw) {
            if (raw is! String) return;
            try {
              final msg = BridgeMessage.fromJson(raw);
              if (msg.type == AL.typePing) {
                ws.add(BridgeMessage(type: AL.typePong, payload: {}).toJson());
                return;
              }
              _messageStream.add(msg);
            } catch (e) {
              _log.e('Parse error', error: e);
            }
          },
          onDone: () => _removeClient(ws),
          onError: (_) => _removeClient(ws),
          cancelOnError: true,
        );
      });
    } catch (e) {
      _log.e('Server start failed', error: e);
    }
  }

  void _removeClient(WebSocket ws) {
    _clients.remove(ws);
    _connectedDevicesCount.add(_clients.length);
    if (_clients.isEmpty) _statusStream.add(BridgeStatus.searching);
    _log.w('Android disconnected. Remaining: ${_clients.length}');
  }

  // ══ MAC: UDP beacon ════════════════════════════════════════════════════

  void _startUdpBroadcast() async {
    if (_localIp == null) return;
    try {
      _udpBroadcastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpBroadcastSocket!.broadcastEnabled = true;
      final msg = utf8.encode('ANDROIDLINK:$_localIp:${AL.wsPort}');

      // Compute subnet broadcast (assume /24: 192.168.x.255)
      final subnetBroadcast = _subnetBroadcast(_localIp!);

      _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        try {
          // Send to both 255.255.255.255 and subnet broadcast
          _udpBroadcastSocket?.send(
              msg, InternetAddress('255.255.255.255'), AL.udpPort);
          if (subnetBroadcast != null) {
            _udpBroadcastSocket?.send(
                msg, InternetAddress(subnetBroadcast), AL.udpPort);
          }
        } catch (_) {}
      });
      _log.i('UDP broadcast started: $_localIp → $subnetBroadcast');
    } catch (e) {
      _log.e('UDP broadcast failed: $e');
    }
  }

  String? _subnetBroadcast(String ip) {
    try {
      final parts = ip.split('.');
      if (parts.length != 4) return null;
      return '${parts[0]}.${parts[1]}.${parts[2]}.255';
    } catch (_) {
      return null;
    }
  }

  // ══ ANDROID: UDP listener ══════════════════════════════════════════════

  Future<void> _listenForMacUdp() async {
    _statusStream.add(BridgeStatus.searching);
    try {
      _udpListenSocket?.close();
      _udpListenSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, AL.udpPort);
      _log.i('Listening for Mac on UDP :${AL.udpPort}');

      _udpListenSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _udpListenSocket?.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data);
        if (!msg.startsWith('ANDROIDLINK:')) return;
        final parts = msg.split(':');
        if (parts.length < 3) return;
        final ip = parts[1];
        _log.i('Found Mac at $ip via UDP beacon');
        _udpListenSocket?.close();
        _udpListenSocket = null;
        _connectToMac(ip);
      });
    } catch (e) {
      _log.e('UDP listen failed: $e');
      _reconnectTimer?.cancel();
      _reconnectTimer =
          Timer(const Duration(seconds: 5), _listenForMacUdp);
    }
  }

  Future<void> connectToMacDirectly(String ip) async {
    _lastMacIp = ip;
    _udpListenSocket?.close();
    _udpListenSocket = null;
    _connectToMac(ip);
  }

  /// Подключение через QR: данные вида "androidlink://192.168.x.x:41234"
  Future<void> connectViaQr(String qrValue) async {
    final uri = Uri.tryParse(qrValue);
    if (uri == null || uri.scheme != 'androidlink') return;
    final ip = uri.host;
    if (ip.isEmpty) return;
    connectToMacDirectly(ip);
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
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_lastMacIp != null) {
        _connectToMac(_lastMacIp!);
      } else {
        _listenForMacUdp();
      }
    });
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
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    if (isMac) {
      final json = message.toJson();
      for (final ws in List.of(_clients)) {
        try { ws.add(json); } catch (_) {}
      }
    } else {
      if (!isConnected) return;
      _channel?.sink.add(message.toJson());
    }
  }

  void sendRaw(Map<String, dynamic> payload, String type) =>
      send(BridgeMessage(type: type, payload: payload, id: _uuid.v4()));

  void _onDisconnected() {
    _log.w('Disconnected from Mac');
    _statusStream.add(BridgeStatus.disconnected);
    _heartbeatTimer?.cancel();
    _scheduleReconnect();
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
    _broadcastTimer?.cancel();
    _udpBroadcastSocket?.close();
    _udpListenSocket?.close();
    _channel?.sink.close();
    _channel = null;
    for (final ws in List.of(_clients)) {
      try { ws.close(); } catch (_) {}
    }
    _clients.clear();
    _statusStream.add(BridgeStatus.disconnected);
  }
}
