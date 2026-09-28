class UploadResponseParser {
  static String parseUrl({
    required String responseBody,
    required String regex,
  }) {
    final body = responseBody.trim();

    if (regex.trim().isEmpty) {
      final urlMatch = RegExp(r'https?://\S+', multiLine: true).firstMatch(body);
      if (urlMatch != null) {
        return urlMatch.group(0)!;
      }
      return body;
    }

    final regExp = RegExp(regex.trim(), multiLine: true);
    final match = regExp.firstMatch(body);

    if (match == null) {
      throw const FormatException('Upload response did not match regex');
    }

    if (match.groupCount >= 1) {
      return match.group(1) ?? match.group(0) ?? '';
    }

    return match.group(0) ?? '';
  }
}
