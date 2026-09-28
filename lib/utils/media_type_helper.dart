import 'package:http_parser/http_parser.dart';

class MediaTypeHelper {
  static MediaType parse(String mimeType) {
    final parts = mimeType.split('/');

    if (parts.length != 2) {
      return MediaType('application', 'octet-stream');
    }

    return MediaType(parts[0], parts[1]);
  }
}
