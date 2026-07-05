import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // للتحقق من كونه ويب أو موبايل
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';

class ChatUploadService {
  final String serverUrl;

  ChatUploadService(this.serverUrl);

  /// دالة لرفع صورة الدردشة بنفس منطق كود البروفايل
  Future<String?> uploadChatImage() async {
    final ImagePicker picker = ImagePicker();

    // اختيار الصورة
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // تقليل الجودة لتسريع الرفع كما في البروفايل
    );

    if (image == null) return null;

    try {
      // تجهيز الطلب بصيغة Multipart
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$serverUrl/chat/upload"),
      );

      // قراءة الملف كـ Bytes (متوافق مع الويب والموبايل)
      final Uint8List fileBytes = await image.readAsBytes();

      // استخراج الامتداد
      String fileExtension = image.path.split('.').last.toLowerCase();
      if (fileExtension == 'jpg') fileExtension = 'jpeg';

      // إضافة الملف للطلب بنفس مفتاح السيرفر 'chat_file'
      request.files.add(
        http.MultipartFile.fromBytes(
          'chat_file', // المفتاح الذي ينتظره multer
          fileBytes,
          filename: image.name,
          contentType: MediaType('image', fileExtension),
        ),
      );

      // إرسال الطلب واستلام الرد بنفس أسلوب كود البروفايل
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);

        // إذا كان السيرفر يعيد الحقل باسم 'url'
        return responseData['url'];
      } else {
        print("خطأ السيرفر: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("حدث خطأ أثناء الرفع: $e");
      return null;
    }
  }

  /// دالة مساعدة للحصول على الرابط الكامل للصورة مع منع الكاش (Cache Bursting)
  /// تماماً كما فعلت في دالة _getFullImageUrl
  String? getFullChatImageUrl(String? fileName) {
    if (fileName == null || fileName.isEmpty || fileName == "null") return null;
    if (fileName.startsWith('http')) return fileName;

    // إضافة timestamp لمنع المتصفح من عرض الصورة القديمة من الذاكرة
    return "$serverUrl/uploads/$fileName?v=${DateTime.now().millisecondsSinceEpoch}";
  }
}
