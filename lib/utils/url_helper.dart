/// Helpers for finding and normalizing URLs in chat messages.
class UrlHelper {
  // Matches, in order:
  //   1. http(s) URLs with optional user-info, an IPv4/IPv6/localhost/hostname
  //      host, optional port, and optional path/query/fragment.
  //   2. Bare IPv4 addresses that include a port and optional path.
  //   3. Bare hostnames with optional port and path.
  //   4. localhost with a port and optional path.
  //
  // Requiring a port for bare IPv4 addresses avoids treating version strings
  // such as 1.2.3.4 as links.
  static final RegExp urlRegex = RegExp(
    r'(?:https?://(?:[^/\s@]+@)?'
    r'(?:(?:\d{1,3}\.){3}\d{1,3}'
    r'|\[[0-9a-fA-F:.]+\]'
    r'|localhost'
    r'|(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,})'
    r'(?::\d{1,5})?'
    r'(?:[/?#][^\s]*)?)'
    r'|(?:(?:\d{1,3}\.){3}\d{1,3}:\d{1,5}(?:/[^\s]*)?'
    r'|(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(?::\d{1,5})?(?:/[^\s]*)?'
    r'|localhost:\d{1,5}(?:/[^\s]*)?)',
    caseSensitive: false,
  );

  static final RegExp _tokenChar = RegExp(r'[a-zA-Z0-9@/._-]');

  /// Returns URL matches that start at a token boundary.
  ///
  /// The boundary check stops the bare-hostname alternative from matching a
  /// file name inside a longer URL that the full-URL alternative could not
  /// parse (for example "cam.png" in "ftp://host/cam.png").
  static Iterable<RegExpMatch> matches(String text) sync* {
    for (final match in urlRegex.allMatches(text)) {
      if (match.start > 0 && _tokenChar.hasMatch(text[match.start - 1])) {
        continue;
      }
      yield match;
    }
  }

  static List<String> extractUrls(String text) {
    return matches(text)
        .map((match) => match.group(0) ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
  }

  static String normalizeUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    return 'https://$url';
  }

  static bool hasUrl(String text) {
    return matches(text).isNotEmpty;
  }
}
