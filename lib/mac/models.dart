/// Data the Mac keeps about the phone. JSON round-trip for local history.
library;

import 'dart:typed_data';

String normalizeNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return raw.trim().toLowerCase(); // alphanumeric senders
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

class SmsMsg {
  SmsMsg({
    required this.id,
    required this.address,
    required this.body,
    required this.ts,
    required this.incoming,
    this.status = 'sent',
    this.read = true,
  });

  final String id;
  final String address;
  final String body;
  final int ts;
  final bool incoming;
  String status; // sending | sent | failed | received
  bool read;

  bool get isLocal => id.startsWith('local:');
  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);

  factory SmsMsg.fromJson(Map<String, dynamic> j) => SmsMsg(
        id: j['id'] as String? ?? '',
        address: j['address'] as String? ?? '',
        body: j['body'] as String? ?? '',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        incoming: j['in'] as bool? ?? false,
        status: j['status'] as String? ?? 'sent',
        read: j['read'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'address': address, 'body': body, 'ts': ts,
        'in': incoming, 'status': status, 'read': read,
      };
}

class SmsThread {
  SmsThread(this.key, this.address);
  final String key;
  String address;
  final List<SmsMsg> messages = [];

  SmsMsg? get last => messages.isEmpty ? null : messages.last;
  int get unread => messages.where((m) => m.incoming && !m.read).length;
}

class CallEntry {
  CallEntry({
    required this.id,
    required this.address,
    required this.type,
    required this.ts,
    this.dur = 0,
    this.name,
  });

  final String id;
  final String address;
  final String type; // incoming | outgoing | missed | rejected
  final int ts;
  final int dur;
  final String? name;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);

  factory CallEntry.fromJson(Map<String, dynamic> j) => CallEntry(
        id: j['id'] as String? ?? '',
        address: j['address'] as String? ?? '',
        type: j['type'] as String? ?? 'incoming',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        dur: (j['dur'] as num?)?.toInt() ?? 0,
        name: j['name'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'address': address, 'type': type, 'ts': ts, 'dur': dur, 'name': name};
}

/// The call happening right now (ringing / dialing / in progress).
class LiveCall {
  LiveCall({required this.id, required this.address, required this.state, required this.incoming, this.name});
  final String id;
  final String address;
  String state; // ringing | dialing | answered
  final bool incoming;
  final String? name;
  DateTime since = DateTime.now();
}

class PhoneNotif {
  PhoneNotif({
    required this.key,
    required this.app,
    required this.pkg,
    required this.title,
    required this.body,
    required this.ts,
    required this.canReply,
  });

  final String key;
  final String app;
  final String pkg;
  final String title;
  final String body;
  final int ts;
  final bool canReply;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);

  factory PhoneNotif.fromJson(Map<String, dynamic> j) => PhoneNotif(
        key: j['key'] as String? ?? '${j['pkg']}:${j['ts']}',
        app: j['app'] as String? ?? '',
        pkg: j['pkg'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        ts: (j['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        canReply: j['canReply'] as bool? ?? false,
      );
}

class ClipEntry {
  ClipEntry(this.text, this.fromPhone, {this.image}) : time = DateTime.now();
  final String text;
  final Uint8List? image;
  final bool fromPhone;
  final DateTime time;
}

class Contact {
  Contact(this.name, this.numbers);
  final String name;
  final List<String> numbers;

  factory Contact.fromJson(Map<String, dynamic> j) =>
      Contact(j['name'] as String? ?? '', (j['numbers'] as List? ?? const []).cast<String>());
  Map<String, dynamic> toJson() => {'name': name, 'numbers': numbers};
}
