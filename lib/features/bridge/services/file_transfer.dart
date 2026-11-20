import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/constants/app_constants.dart';
import 'bridge_service.dart';
import 'link_crypto.dart';

/// One file going in or out.
class Transfer {
  Transfer({
    required this.fid,
    required this.name,
    required this.size,
    required this.incoming,
    this.deviceId,
  });

  final String fid;
  final String name;
  final int size;
  final bool incoming;
  final String? deviceId;
  int done = 0;
  bool finished = false;
  bool failed = false;
  String? path;
  final DateTime started = DateTime.now();

  double get progress => size > 0 ? (done / size).clamp(0, 1).toDouble() : (finished ? 1 : 0);
}

class _Rx {
  _Rx(this.t, this.tmp, this.sink);
  final Transfer t;
  final File tmp;
  final IOSink sink;
  int next = 0;
}

/// Mac side of the chunked file protocol (see FileTransfer.kt for the spec).
class FileTransferHub {
  FileTransferHub._();
  static final FileTransferHub instance = FileTransferHub._();

  static const _chunk = 192 * 1024;
  static const _window = 24;
  static const _ackEvery = 8;

  final _list = BehaviorSubject<List<Transfer>>.seeded(const []);
  final _received = StreamController<Transfer>.broadcast();
  final Map<String, _Rx> _rx = {};
  final Map<String, int> _acked = {};
  final Set<String> _cancelled = {};
  final List<Transfer> _all = [];
  StreamSubscription? _sub;

  Stream<List<Transfer>> get transfers => _list.stream;
  List<Transfer> get current => _list.value;

  /// Fires when an incoming file is saved.
  Stream<Transfer> get received => _received.stream;

  Future<void> _chain = Future.value();

  void start() {
    // Handlers await file I/O — chain them so chunks are processed in order.
    _sub ??= BridgeService.instance.messages.listen((m) {
      if (!m.type.startsWith('file_')) return;
      _chain = _chain.then((_) => _onMessage(m)).catchError((Object _) {});
    });
  }

  void _emit() => _list.add(List.unmodifiable(_all.reversed));

  void clearFinished() {
    _all.removeWhere((t) => t.finished || t.failed);
    _emit();
  }

  void cancel(String fid) {
    _cancelled.add(fid);
    final rx = _rx.remove(fid);
    if (rx != null) {
      rx.sink.close();
      rx.tmp.delete().catchError((_) => rx.tmp);
      rx.t.failed = true;
      BridgeService.instance.sendRaw({'fid': fid}, AL.typeFileCancel, deviceId: rx.t.deviceId);
    }
    _emit();
  }

  // ── send ──

  Future<void> sendFile(File f, {required String deviceId}) async {
    final fid = LinkCrypto.randomId();
    final size = await f.length();
    final name = f.uri.pathSegments.last;
    final t = Transfer(fid: fid, name: name, size: size, incoming: false, deviceId: deviceId);
    _all.add(t);
    _emit();
    final b = BridgeService.instance;
    _acked[fid] = -1;
    b.sendRaw({'fid': fid, 'name': name, 'size': size, 'mime': _mime(name)}, AL.typeFileOffer,
        deviceId: deviceId);
    RandomAccessFile? raf;
    var seq = 0;
    try {
      raf = await f.open();
      while (true) {
        final bytes = await raf.read(_chunk);
        if (bytes.isEmpty) break;
        var waited = 0;
        while (seq - (_acked[fid] ?? -1) > _window) {
          if (_aborted(fid, deviceId) || waited > 60000) throw StateError('aborted');
          await Future<void>.delayed(const Duration(milliseconds: 15));
          waited += 15;
        }
        if (_aborted(fid, deviceId)) throw StateError('aborted');
        b.sendRaw({'fid': fid, 'seq': seq, 'data': base64Encode(bytes)}, AL.typeFileChunk,
            deviceId: deviceId);
        seq++;
        t.done += bytes.length;
        if (seq % 4 == 0) _emit();
      }
      b.sendRaw({'fid': fid, 'chunks': seq}, AL.typeFileDone, deviceId: deviceId);
      t.finished = true;
    } catch (_) {
      t.failed = true;
      b.sendRaw({'fid': fid}, AL.typeFileCancel, deviceId: deviceId);
    } finally {
      await raf?.close();
      _acked.remove(fid);
      _cancelled.remove(fid);
      _emit();
    }
  }

  bool _aborted(String fid, String deviceId) =>
      _cancelled.contains(fid) ||
      !BridgeService.instance.currentDevices.any((d) => d.id == deviceId);

  // ── receive ──

  Future<void> _onMessage(BridgeMessage m) async {
    final p = m.payload;
    final fid = p['fid'] as String? ?? '';
    switch (m.type) {
      case AL.typeFileAck:
        final seq = p['seq'] as int? ?? -1;
        if (seq > (_acked[fid] ?? -1)) _acked[fid] = seq;
      case AL.typeFileCancel:
        _cancelled.add(fid);
        final rx = _rx.remove(fid);
        if (rx != null) {
          await rx.sink.close();
          rx.t.failed = true;
          _emit();
        }
      case AL.typeFileOffer:
        final name = safeName(p['name'] as String? ?? 'file');
        final t = Transfer(
            fid: fid, name: name, size: (p['size'] as num?)?.toInt() ?? -1, incoming: true,
            deviceId: m.deviceId);
        final tmp = File('${(await getTemporaryDirectory()).path}/rx-$fid');
        _rx[fid] = _Rx(t, tmp, tmp.openWrite());
        _all.add(t);
        _emit();
      case AL.typeFileChunk:
        final rx = _rx[fid];
        if (rx == null) return;
        final seq = p['seq'] as int? ?? -1;
        if (seq != rx.next) {
          cancel(fid);
          return;
        }
        final Uint8List bytes = base64Decode(p['data'] as String? ?? '');
        rx.sink.add(bytes);
        rx.next++;
        rx.t.done += bytes.length;
        if (rx.next % _ackEvery == 0) {
          BridgeService.instance.sendRaw({'fid': fid, 'seq': seq}, AL.typeFileAck, deviceId: m.deviceId);
        }
        if (rx.next % 4 == 0) _emit();
      case AL.typeFileDone:
        final rx = _rx.remove(fid);
        if (rx == null) return;
        await rx.sink.flush();
        await rx.sink.close();
        BridgeService.instance.sendRaw({'fid': fid, 'seq': rx.next - 1, 'complete': true}, AL.typeFileAck,
            deviceId: m.deviceId);
        try {
          final dest = await _uniqueDest(rx.t.name);
          await rx.tmp.copy(dest.path);
          await rx.tmp.delete();
          rx.t.path = dest.path;
          rx.t.finished = true;
          if (rx.t.size < 0) rx.t.done = await dest.length();
          _received.add(rx.t);
        } catch (_) {
          rx.t.failed = true;
        }
        _emit();
    }
  }

  static String safeName(String n) {
    final s = n.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    final cut = s.length > 180 ? s.substring(0, 180) : s;
    return (cut.isEmpty || cut == '.' || cut == '..') ? 'file' : cut;
  }

  Future<File> _uniqueDest(String name) async {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var f = File('${dir.path}/$name');
    for (var i = 2; await f.exists(); i++) {
      f = File('${dir.path}/$base ($i)$ext');
    }
    return f;
  }

  static String _mime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {
          'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif',
          'heic': 'image/heic', 'webp': 'image/webp', 'mp4': 'video/mp4', 'mov': 'video/quicktime',
          'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'pdf': 'application/pdf', 'txt': 'text/plain',
          'zip': 'application/zip', 'apk': 'application/vnd.android.package-archive',
          'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        }[ext] ??
        'application/octet-stream';
  }
}
