import 'package:equatable/equatable.dart';

class SmsThread extends Equatable {
  const SmsThread({
    required this.address,
    required this.messages,
    this.contactName,
    this.contactAvatar,
  });

  final String address;
  final List<SmsModel> messages;
  final String? contactName;
  final String? contactAvatar;

  String get displayName => contactName ?? address;
  SmsModel? get lastMessage => messages.isEmpty ? null : messages.last;
  int get unreadCount => messages.where((m) => !m.isRead && m.isIncoming).length;

  SmsThread copyWith({List<SmsModel>? messages}) => SmsThread(
        address:       address,
        messages:      messages ?? this.messages,
        contactName:   contactName,
        contactAvatar: contactAvatar,
      );

  @override
  List<Object?> get props => [address, messages];
}

class SmsModel extends Equatable {
  const SmsModel({
    required this.id,
    required this.address,
    required this.body,
    required this.timestamp,
    required this.isIncoming,
    this.isRead = false,
    this.status = SmsStatus.delivered,
  });

  final String    id;
  final String    address;
  final String    body;
  final DateTime  timestamp;
  final bool      isIncoming;
  final bool      isRead;
  final SmsStatus status;

  factory SmsModel.fromMap(Map<String, dynamic> m) => SmsModel(
        id:         m['id'] as String,
        address:    m['address'] as String,
        body:       m['body'] as String,
        timestamp:  DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        isIncoming: (m['in'] as bool?) ?? true,
        isRead:     (m['read'] as bool?) ?? false,
        status:     SmsStatus.values.firstWhere(
          (e) => e.name == (m['status'] as String? ?? 'delivered'),
          orElse: () => SmsStatus.delivered,
        ),
      );

  Map<String, dynamic> toMap() => {
        'id':     id,
        'address':address,
        'body':   body,
        'ts':     timestamp.millisecondsSinceEpoch,
        'in':     isIncoming,
        'read':   isRead,
        'status': status.name,
      };

  SmsModel copyWith({bool? isRead}) => SmsModel(
        id:         id,
        address:    address,
        body:       body,
        timestamp:  timestamp,
        isIncoming: isIncoming,
        isRead:     isRead ?? this.isRead,
        status:     status,
      );

  @override
  List<Object?> get props => [id, isRead, status];
}

enum SmsStatus { sending, delivered, failed }
