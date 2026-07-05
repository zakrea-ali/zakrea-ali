import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';

class FileChatUploadService {
  final String serverUrl;

  FileChatUploadService(this.serverUrl);

  /// رفع ملف واحد
  Future<String?> pickAndUploadFile() async {
    try {
      // ✅ التعديل: حذف .platform
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return null;

      final PlatformFile file = result.files.first;
      if (file.bytes == null) return null;

      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$serverUrl/user/upload_file"),
      );

      final Uint8List fileBytes = file.bytes!;
      String fileExtension = file.extension ?? 'bin';

      request.files.add(
        http.MultipartFile.fromBytes(
          'user_file',
          fileBytes,
          filename: file.name,
          contentType: _getMediaType(fileExtension),
        ),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        return responseData['url'];
      } else {
        print("خطأ السيرفر: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      print("حدث خطأ أثناء الرفع: $e");
      return null;
    }
  }

  /// رفع مجلد كامل (جميع الملفات بداخله)
  Future<List<String>> pickAndUploadFolder() async {
    try {
      // ✅ التعديل: حذف .platform
      String? folderPath = await FilePicker.platform.getDirectoryPath();
      if (folderPath == null) return [];

      List<String> uploadedFiles = [];

      // ✅ التعديل: حذف .platform
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return [];

      for (var file in result.files) {
        if (file.bytes == null) continue;

        var request = http.MultipartRequest(
          'POST',
          Uri.parse("$serverUrl/file/upload"),
        );

        String extension = file.extension ?? 'bin';

        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
            contentType: _getMediaType(extension),
          ),
        );

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          uploadedFiles.add(data['url']);
        } else {
          print("فشل رفع ملف: ${file.name}");
        }
      }

      return uploadedFiles;
    } catch (e) {
      print("خطأ أثناء رفع المجلد: $e");
      return [];
    }
  }

  /// تحديد نوع الملف (MIME)
  MediaType _getMediaType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'doc':
      case 'docx':
        return MediaType('application', 'msword');
      case 'mp4':
        return MediaType('video', 'mp4');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  /// الحصول على الرابط الكامل من مجلد uploads_file
  String? getFullFileUrl(String? fileName) {
    if (fileName == null || fileName.isEmpty || fileName == "null") return null;
    if (fileName.startsWith('http')) return fileName;

    return "$serverUrl/uploads_file/$fileName";
  }
}
