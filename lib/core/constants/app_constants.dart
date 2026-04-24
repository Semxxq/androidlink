class AL {
  AL._();

  // ── Bridge (локальная сеть) ───────────────────────────────────────────
  static const int    wsPort          = 41234;
  static const int    udpPort         = 41235;
  static const Duration wsTimeout     = Duration(seconds: 10);
  static const Duration heartbeat     = Duration(seconds: 5);

  // ── Firestore collections ─────────────────────────────────────────────
  static const String colUsers        = 'al_users';
  static const String colMessages     = 'messages';
  static const String colCalls        = 'calls';
  static const String colNotifications= 'notifications';
  static const String colClipboard    = 'clipboard';

  // ── WebSocket message types ───────────────────────────────────────────
  static const String typeSms         = 'sms';
  static const String typeSmsReply    = 'sms_reply';
  static const String typeCall        = 'call';
  static const String typeNotif       = 'notification';
  static const String typeClipboard   = 'clipboard';
  static const String typeFile        = 'file';
  static const String typeFileChunk   = 'file_chunk';
  static const String typePing        = 'ping';
  static const String typePong        = 'pong';
  static const String typePaired      = 'paired';
  static const String typeContactList = 'contacts';

  // ── Безопасность ─────────────────────────────────────────────────────
  static const String keyPairKey      = 'al_keypair';
  static const String deviceIdKey     = 'al_device_id';
  static const String pairingKey      = 'al_pairing';

  // ── UI ────────────────────────────────────────────────────────────────
  static const double sidebarWidth    = 260.0;
  static const double minWindowWidth  = 900.0;
  static const double minWindowHeight = 600.0;
}
