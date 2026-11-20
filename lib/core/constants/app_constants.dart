/// Protocol constants shared by the Mac and Android sides.
/// Native counterpart: android/app/src/main/kotlin/com/androidlink/LinkService.kt
class AL {
  AL._();

  static const int wsPort = 41234;
  static const int udpPort = 41235;

  // phone → Mac
  static const String typeSms = 'sms';
  static const String typeSmsBatch = 'sms_batch';
  static const String typeSmsStatus = 'sms_status';
  static const String typeCall = 'call';
  static const String typeCallBatch = 'call_batch';
  static const String typeContactsBatch = 'contacts_batch';
  static const String typeNotif = 'notification';
  static const String typeNotifRemoved = 'notification_removed';
  static const String typeDeviceInfo = 'device_info';
  static const String typeBattery = 'battery';
  static const String typeCallResult = 'call_action_result';
  static const String typeNotifReplyResult = 'notification_reply_result';

  // Mac → phone
  static const String typeSmsReply = 'sms_reply';
  static const String typeSmsSync = 'sms_sync';
  static const String typeCallsSync = 'calls_sync';
  static const String typeContactsSync = 'contacts_sync';
  static const String typeCallAction = 'call_action';
  static const String typeCallDial = 'call_dial';
  static const String typeRing = 'ring';
  static const String typeRingStop = 'ring_stop';
  static const String typeNotifDismiss = 'notification_dismiss';
  static const String typeNotifReply = 'notification_reply';

  // both ways
  static const String typeClipboard = 'clipboard';
  static const String typeClipImage = 'clip_image';
  static const String typeFileOffer = 'file_offer';
  static const String typeFileChunk = 'file_chunk';
  static const String typeFileAck = 'file_ack';
  static const String typeFileDone = 'file_done';
  static const String typeFileCancel = 'file_cancel';
}
