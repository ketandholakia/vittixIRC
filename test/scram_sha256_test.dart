import 'package:flutter_test/flutter_test.dart';

import 'package:vittix_irc/core/scram_sha256.dart';

void main() {
  // Test vectors from RFC 7677, section 3 ("SCRAM-SHA-256 Example").
  // username 'user', password 'pencil'.
  const serverFirst =
      'r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0,'
      's=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096';
  const expectedClientFinal =
      'c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0,'
      'p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=';
  const serverFinal = 'v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=';

  group('SCRAM-SHA-256 (RFC 7677 vectors)', () {
    test('full exchange produces the RFC client-final-message', () {
      final scram = ScramSha256Client(
        username: 'user',
        clientNonce: 'rOprNGfwEbeRWgbNEkqO',
      );

      expect(scram.start(), 'n,,n=user,r=rOprNGfwEbeRWgbNEkqO');

      final clientFinal = scram.handleServerFirst(serverFirst, 'pencil');

      expect(clientFinal, expectedClientFinal);
    });

    test('accepts a matching server-final-message', () {
      final scram = ScramSha256Client(
        username: 'user',
        clientNonce: 'rOprNGfwEbeRWgbNEkqO',
      );
      scram.start();
      scram.handleServerFirst(serverFirst, 'pencil');

      expect(scram.verifyServerFinal(serverFinal), isTrue);
    });

    test('rejects a forged server-final-message', () {
      final scram = ScramSha256Client(
        username: 'user',
        clientNonce: 'rOprNGfwEbeRWgbNEkqO',
      );
      scram.start();
      scram.handleServerFirst(serverFirst, 'pencil');

      expect(
        scram.verifyServerFinal('v=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
        isFalse,
      );
    });

    test('rejects a server nonce that does not extend the client nonce', () {
      final scram = ScramSha256Client(
        username: 'user',
        clientNonce: 'rOprNGfwEbeRWgbNEkqO',
      );
      scram.start();

      final tampered = serverFirst.replaceFirst(
        'r=rOprNGfwEbeRWgbNEkqO%',
        'r=DIFFERENT_NONCE%',
      );

      expect(scram.handleServerFirst(tampered, 'pencil'), isNull);
    });

    test('rejects unsupported mandatory extensions', () {
      final scram = ScramSha256Client(
        username: 'user',
        clientNonce: 'rOprNGfwEbeRWgbNEkqO',
      );
      scram.start();

      expect(
        scram.handleServerFirst('$serverFirst,m=unexpected', 'pencil'),
        isNull,
      );
    });

    test('wrong password produces a different proof', () {
      final scram = ScramSha256Client(
        username: 'user',
        clientNonce: 'rOprNGfwEbeRWgbNEkqO',
      );
      scram.start();

      final clientFinal = scram.handleServerFirst(serverFirst, 'pencils');

      expect(clientFinal, isNot(expectedClientFinal));
    });
  });

  group('SCRAM-SHA-256 (general behavior)', () {
    test('escapes = and , in usernames', () {
      final scram = ScramSha256Client(
        username: 'weird,nick=x',
        clientNonce: 'abc',
      );

      expect(scram.start(), startsWith('n,,n=weird=2Cnick=3Dx,r='));
    });

    test('generates a random nonce when none is given', () {
      final scram = ScramSha256Client(username: 'user');
      final message = scram.start();

      expect(message, matches(RegExp(r'^n,,n=user,r=[A-Za-z0-9+/]{20,}$')));
    });
  });
}
