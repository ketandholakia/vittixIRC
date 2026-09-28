import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class BackupCrypto {
  static const int _keyLength = 32;
  static const int _saltLength = 16;

  static String encryptJson({
    required Map<String, dynamic> json,
    required String password,
  }) {
    final salt = _randomBytes(_saltLength);
    final key = _deriveKey(password, salt);
    final iv = IV.fromSecureRandom(16);

    final encrypter = Encrypter(
      AES(
        Key(key),
        mode: AESMode.cbc,
        padding: 'PKCS7',
      ),
    );

    final plainText = jsonEncode(json);
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    return jsonEncode({
      'encrypted': true,
      'version': 1,
      'algorithm': 'AES-256-CBC',
      'kdf': 'SHA256',
      'salt': base64Encode(salt),
      'iv': iv.base64,
      'data': encrypted.base64,
    });
  }

  static Map<String, dynamic> decryptJson({
    required String encryptedText,
    required String password,
  }) {
    final wrapper = jsonDecode(encryptedText) as Map<String, dynamic>;

    if (wrapper['encrypted'] != true) {
      throw const FormatException('Backup is not encrypted');
    }

    final salt = base64Decode(wrapper['salt'] as String);
    final key = _deriveKey(password, salt);
    final iv = IV.fromBase64(wrapper['iv'] as String);

    final encrypter = Encrypter(
      AES(
        Key(key),
        mode: AESMode.cbc,
        padding: 'PKCS7',
      ),
    );

    final encrypted = Encrypted.fromBase64(wrapper['data'] as String);
    final decrypted = encrypter.decrypt(encrypted, iv: iv);

    return jsonDecode(decrypted) as Map<String, dynamic>;
  }

  static Uint8List _deriveKey(String password, List<int> salt) {
    var bytes = utf8.encode(password) + salt;

    for (var i = 0; i < 10000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }

    return Uint8List.fromList(bytes.take(_keyLength).toList());
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }
}
