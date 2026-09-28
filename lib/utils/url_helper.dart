class UrlHelper {
  static final RegExp urlRegex = RegExp(
    r'((https?:\/\/)?([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(\/[^\s]*)?)',
    caseSensitive: false,
  );

  static List<String> extractUrls(String text) {
    return urlRegex
        .allMatches(text)
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
    return extractUrls(text).isNotEmpty;
  }
}
