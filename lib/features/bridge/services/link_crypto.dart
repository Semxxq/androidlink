import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-256-GCM. Wire frame = base64(nonce[12] || ciphertext || tag[16]).
/// Must match android/.../LinkCrypto.kt.
class LinkCrypto {
  LinkCrypto._();

  static final _aes = AesGcm.with256bits();
  static final _rnd = Random.secure();

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _rnd.nextInt(256)));

  static String randomId() =>
      base64Url.encode(randomBytes(12)).replaceAll('=', '');

  static Future<String> seal(SecretKey key, String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: key);
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<String?> open(SecretKey key, String frame) async {
    try {
      final b = base64Decode(frame);
      if (b.length < 28) return null;
      final box = SecretBox(
        b.sublist(12, b.length - 16),
        nonce: b.sublist(0, 12),
        mac: Mac(b.sublist(b.length - 16)),
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: key));
    } catch (_) {
      return null;
    }
  }
}
