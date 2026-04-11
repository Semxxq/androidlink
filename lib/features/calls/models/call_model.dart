import 'package:equatable/equatable.dart';

enum CallType { incoming, outgoing, missed }

class CallModel extends Equatable {
  const CallModel({
    required this.id,
    required this.address,
    required this.type,
    required this.timestamp,
    this.duration,
    this.contactName,
    this.contactAvatar,
    this.isActive = false,
  });

  final String    id;
  final String    address;
  final CallType  type;
  final DateTime  timestamp;
  final Duration? duration;
  final String?   contactName;
  final String?   contactAvatar;
  final bool      isActive; // Сейчас идёт звонок

  String get displayName => contactName ?? address;

  factory CallModel.fromMap(Map<String, dynamic> m) => CallModel(
        id:           m['id'] as String,
        address:      m['address'] as String,
        type:         CallType.values.firstWhere(
          (e) => e.name == (m['type'] as String? ?? 'incoming'),
        ),
        timestamp:    DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
        duration:     m['dur'] != null
            ? Duration(seconds: m['dur'] as int)
            : null,
        contactName:  m['name'] as String?,
        contactAvatar:m['avatar'] as String?,
        isActive:     (m['active'] as bool?) ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id':     id,
        'address':address,
        'type':   type.name,
        'ts':     timestamp.millisecondsSinceEpoch,
        'dur':    duration?.inSeconds,
        'name':   contactName,
        'avatar': contactAvatar,
        'active': isActive,
      };

  @override
  List<Object?> get props => [id, isActive];
}
