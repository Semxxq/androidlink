import 'package:androidlink/features/bridge/services/link_crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seal/open roundtrip and tamper detection', () async {
    final key = SecretKey(LinkCrypto.randomBytes(32));
    final frame = await LinkCrypto.seal(key, '{"type":"sms","payload":{"body":"привет"}}');
    expect(await LinkCrypto.open(key, frame), contains('привет'));

    final other = SecretKey(LinkCrypto.randomBytes(32));
    expect(await LinkCrypto.open(other, frame), isNull);
    expect(await LinkCrypto.open(key, 'garbage'), isNull);
  });
}
