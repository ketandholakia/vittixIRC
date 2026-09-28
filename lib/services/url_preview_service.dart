import 'package:http/http.dart' as http;

class UrlPreviewData {
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? contentType;

  UrlPreviewData({
    this.title,
    this.description,
    this.imageUrl,
    this.contentType,
  });
}

class UrlPreviewService {
  static final Map<String, Future<UrlPreviewData?>> _previewCache = {};
  static final Map<String, Future<String?>> _contentTypeCache = {};
  static final RegExp _titleRegex =
      RegExp(r'<meta property="og:title" content="([^"]+)"');
  static final RegExp _descRegex =
      RegExp(r'<meta property="og:description" content="([^"]+)"');
  static final RegExp _imageRegex =
      RegExp(r'<meta property="og:image" content="([^"]+)"');
  static final RegExp _urlRegex = RegExp(
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)');

  /// Extracts the first URL from a message string
  static String? extractFirstUrl(String message) {
    final match = _urlRegex.firstMatch(message);
    return match?.group(0);
  }

  /// Fetches the webpage in the background and parses OpenGraph tags
  static Future<UrlPreviewData?> fetchPreview(String url) async {
    if (_previewCache.containsKey(url)) {
      return _previewCache[url];
    }

    final future = _fetchPreview(url);
    _previewCache[url] = future;
    return future;
  }

  static Future<UrlPreviewData?> _fetchPreview(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final html = response.body;

      final titleMatch = _titleRegex.firstMatch(html);
      final descMatch = _descRegex.firstMatch(html);
      final imageMatch = _imageRegex.firstMatch(html);

      if (titleMatch == null && imageMatch == null) return null;

      return UrlPreviewData(
        title: titleMatch?.group(1),
        description: descMatch?.group(1),
        imageUrl: imageMatch?.group(1),
        contentType: response.headers['content-type'],
      );
    } catch (e) {
      // Silently fail if the URL is invalid or host is unreachable
      // Since IRC gets a lot of raw links, we don't want to throw errors
      // that disrupt the chat UI.
      return null;
    }
  }

  static Future<String?> fetchContentType(String url) async {
    if (_contentTypeCache.containsKey(url)) {
      return _contentTypeCache[url];
    }

    final future = _fetchContentType(url);
    _contentTypeCache[url] = future;
    return future;
  }

  static Future<String?> _fetchContentType(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    try {
      final headResponse =
          await http.head(uri).timeout(const Duration(seconds: 5));
      final header = headResponse.headers['content-type'];
      if (header != null && header.isNotEmpty) return header;
    } catch (_) {}

    try {
      final request = http.Request('GET', uri);
      final streamed = await request.send().timeout(const Duration(seconds: 5));
      return streamed.headers['content-type'];
    } catch (_) {
      return null;
    }
  }
}
