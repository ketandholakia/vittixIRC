import 'dart:io';
import 'package:http/http.dart' as http;

class HttpUploadService {
  // 0x0.st is a popular null-pointer pastebin often used by IRC users.
  // It returns the raw URL of the uploaded file as plain text.
  static const String defaultUploadUrl = 'https://0x0.st';

  /// Uploads a file and returns the hosted URL.
  Future<String> uploadFile(File file, {String? customUrl}) async {
    final url = Uri.parse(customUrl ?? defaultUploadUrl);
    
    final request = http.MultipartRequest('POST', url)
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    
    if (response.statusCode == 200) {
      // The response is usually just the URL, e.g., "https://0x0.st/HDF2.jpg\n"
      final responseData = await response.stream.bytesToString();
      return responseData.trim(); 
    } else {
      final errorData = await response.stream.bytesToString();
      throw Exception(
          'Upload failed (Status ${response.statusCode}): $errorData');
    }
  }
}