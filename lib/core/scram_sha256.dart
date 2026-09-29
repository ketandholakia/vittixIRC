import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Client side of SCRAM-SHA-256 (RFC 5802 / RFC 7677).
///
/// Proves knowledge of the password to the server without ever transmitting
/// it. Used as the preferred SASL mechanism when the server advertises it.
///
/// Flow:
///   [start]                    -> client-first-message ("n,,n=...,r=...")
///   [handleServerFirst]        -> client-final-message ("c=biws,r=...,p=...")
///   [verifyServerFinal]        -> true when the server proof (v=...) matches
class ScramSha256Client {
  ScramSha256Client({
    required String username,
    String? clientNonce,
  })  : _username = _escapeUsername(username),
        _clientNonce = clientNonce ?? _generateNonce();

  final String _username;
  final String _clientNonce;

  String? _clientFirstBare;
  String? _serverFirst;
  String? _clientFinalWithoutProof;
  List<int>? _storedKey;
  List<int>? _serverKey;

  /// Builds the client-first-message including the gs2 header ("n,," =
  /// no authorization identity, no channel binding).
  String start() {
    _clientFirstBare = 'n=$_username,r=$_clientNonce';
    return 'n,,$_clientFirstBare';
  }

  /// Consumes the server-first-message and the password, returning the
  /// client-final-message with proof, or null when the server response is
  /// malformed / the nonces do not line up.
  String? handleServerFirst(String serverFirstMessage, String password) {
    final attrs = <String, String>{};

    for (final part in serverFirstMessage.split(',')) {
      final eq = part.indexOf('=');
      if (eq <= 0) return null;
      attrs[part.substring(0, eq)] = part.substring(eq + 1);
    }

    // A mandatory extension we do not understand must fail the exchange.
    if (attrs.containsKey('m')) return null;

    final serverNonce = attrs['r'];
    final saltB64 = attrs['s'];
    final iterationsRaw = attrs['i'];

    if (serverNonce == null ||
        saltB64 == null ||
        iterationsRaw == null ||
        _clientFirstBare == null) {
      return null;
    }

    if (!serverNonce.startsWith(_clientNonce)) return null;

    final iterations = int.tryParse(iterationsRaw);
    if (iterations == null || iterations < 1 || iterations > 10000000) {
      return null;
    }

    List<int> salt;
    try {
      salt = base64Decode(saltB64);
    } on FormatException {
      return null;
    }

    final saltedPassword = _pbkdf2Sha256(
      utf8.encode(password),
      salt,
      iterations,
    );

    final clientKey =
        Hmac(sha256, saltedPassword).convert(utf8.encode('Client Key')).bytes;
    _storedKey = sha256.convert(clientKey).bytes;
    _serverKey =
        Hmac(sha256, saltedPassword).convert(utf8.encode('Server Key')).bytes;

    _serverFirst = serverFirstMessage;
    _clientFinalWithoutProof = 'c=biws,r=$serverNonce';

    final authMessage = utf8.encode(
      '$_clientFirstBare,$_serverFirst,$_clientFinalWithoutProof',
    );
    final clientSignature =
        Hmac(sha256, _storedKey!).convert(authMessage).bytes;

    final proof = List<int>.generate(
      clientKey.length,
      (i) => clientKey[i] ^ clientSignature[i],
    );

    return '$_clientFinalWithoutProof,p=${base64Encode(proof)}';
  }

  /// Verifies the server-final-message ("v=<base64>"), proving the server
  /// also derived the same key material. Returns false when the exchange is
  /// not complete or the proof does not match.
  bool verifyServerFinal(String serverFinalMessage) {
    if (_serverKey == null ||
        _clientFirstBare == null ||
        _clientFinalWithoutProof == null) {
      return false;
    }
    if (!serverFinalMessage.startsWith('v=')) return false;

    final authMessage = utf8.encode(
      '$_clientFirstBare,$_serverFirst,$_clientFinalWithoutProof',
    );
    final expected =
        base64Encode(Hmac(sha256, _serverKey!).convert(authMessage).bytes);

    return serverFinalMessage.substring(2) == expected;
  }

  /// PBKDF2-HMAC-SHA256 for a single 32-byte output block (dkLen == hash
  /// length), which is all SCRAM needs for the salted password.
  static List<int> _pbkdf2Sha256(
    List<int> password,
    List<int> salt,
    int iterations,
  ) {
    final hmac = Hmac(sha256, password);

    var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.from(block);

    for (var i = 1; i < iterations; i++) {
      block = hmac.convert(block).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= block[j];
      }
    }

    return out;
  }

  /// SASLprep is only approximated here: ASCII usernames pass through and the
  /// two characters with special meaning in SCRAM messages are escaped.
  static String _escapeUsername(String username) {
    return username
        .replaceAll('=', '=3D')
        .replaceAll(',', '=2C')
        .trim();
  }

  static String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }
}
