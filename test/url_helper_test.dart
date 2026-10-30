import 'package:flutter_test/flutter_test.dart';

import 'package:vittix_irc/utils/url_helper.dart';

void main() {
  group('UrlHelper.extractUrls', () {
    test('keeps scheme IPv4 URL with port and path intact', () {
      const message = 'join at https://192.168.1.10:18443/cam.png now';
      expect(
        UrlHelper.extractUrls(message),
        ['https://192.168.1.10:18443/cam.png'],
      );
    });

    test('does not linkify the file name inside an IPv4 URL', () {
      final urls = UrlHelper.extractUrls('https://10.0.0.5:18081/pic.png');
      expect(urls, ['https://10.0.0.5:18081/pic.png']);
      expect(urls, isNot(contains('pic.png')));
    });

    test('keeps IPv6 URL with port intact', () {
      expect(
        UrlHelper.extractUrls('http://[2001:db8::1]:8080/status'),
        ['http://[2001:db8::1]:8080/status'],
      );
    });

    test('keeps scheme-less IPv4 URL with port', () {
      expect(
        UrlHelper.extractUrls('host is 192.168.1.5:8080/status'),
        ['192.168.1.5:8080/status'],
      );
    });

    test('keeps hostname with port and path', () {
      expect(
        UrlHelper.extractUrls('see example.com:8443/report'),
        ['example.com:8443/report'],
      );
    });

    test('keeps a normal https URL', () {
      expect(
        UrlHelper.extractUrls('visit https://example.com/path?q=1'),
        ['https://example.com/path?q=1'],
      );
    });

    test('does not linkify a domain inside an email address', () {
      expect(UrlHelper.extractUrls('mail me at alice@example.com'), isEmpty);
    });

    test('does not treat version numbers as URLs', () {
      expect(UrlHelper.extractUrls('release 1.2.3 built today'), isEmpty);
    });

    test('extracts multiple URLs in order', () {
      expect(
        UrlHelper.extractUrls(
          'a https://one.example.com b http://10.0.0.2:8080/two.png',
        ),
        ['https://one.example.com', 'http://10.0.0.2:8080/two.png'],
      );
    });
  });

  group('UrlHelper.matches', () {
    test('returns the full IPv4 URL as a single match', () {
      const message = 'https://192.168.1.10:18443/cam.png';
      final matches = UrlHelper.matches(message).toList();
      expect(matches, hasLength(1));
      expect(matches.single.start, 0);
      expect(matches.single.end, message.length);
    });
  });

  group('UrlHelper.hasUrl', () {
    test('detects an IPv4 URL', () {
      expect(UrlHelper.hasUrl('go to https://10.0.0.5:18081/pic.png'), isTrue);
    });

    test('returns false for plain text', () {
      expect(UrlHelper.hasUrl('no links here'), isFalse);
    });
  });
}
