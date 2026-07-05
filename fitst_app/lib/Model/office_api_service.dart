import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../Model/office_status.dart'; // يجب أن يحتوي الـ model على ownerName و ownerAvatarUrl

class OfficeApiService {
  final String baseUrl;
  OfficeApiService(this.baseUrl);

  // جلب جميع الحالات النشطة مع بيانات رافع الحالة
  Future<List<OfficeStatus>> fetchOfficeStatuses() async {
    final response = await http.get(Uri.parse('$baseUrl/office/status'));
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] == true) {
        List<dynamic> list = data['data'];
        return list.map((item) => OfficeStatus.fromJson(item)).toList();
      } else {
        throw Exception(data['message'] ?? 'فشل تحميل البيانات');
      }
    } else {
      throw Exception('خطأ في السيرفر: ${response.statusCode}');
    }
  }

  // جلب السجل التاريخي
  Future<List<OfficeHistory>> fetchHistory({
    String? officeName,
    String? shift,
  }) async {
    String url = '$baseUrl/office/history';
    final List<String> queryParams = [];
    if (officeName != null && officeName.isNotEmpty) {
      queryParams.add('office_name=$officeName');
    }
    if (shift != null && (shift == 'morning' || shift == 'evening')) {
      queryParams.add('shift=$shift');
    }
    if (queryParams.isNotEmpty) {
      url += '?' + queryParams.join('&');
    }
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] == true) {
        List<dynamic> list = data['data'];
        return list.map((item) => OfficeHistory.fromJson(item)).toList();
      } else {
        throw Exception(data['message']);
      }
    } else {
      throw Exception('فشل تحميل السجل');
    }
  }

  // حفظ حالة مكتب (إضافة أو تعديل)
  Future<void> saveOfficeStatus({
    required String officeName,
    required String shift,
    required String status,
    List<String>? problemType,
    String? problemDetails,
    String? imageUrl,
    required String userId,
    Uint8List? imageBytes,
  }) async {
    final uri = Uri.parse('$baseUrl/office/status');
    final request = http.MultipartRequest('POST', uri);

    request.fields['office_name'] = officeName;
    request.fields['shift'] = shift;
    request.fields['status'] = status;
    request.fields['user_id'] = userId; // يُستخدم لتحديد رافع الحالة
    if (problemType != null && problemType.isNotEmpty) {
      request.fields['problem_type'] = json.encode(problemType);
    }
    if (problemDetails != null && problemDetails.isNotEmpty) {
      request.fields['problem_details'] = problemDetails;
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      request.fields['image_url'] = imageUrl;
    }

    if (imageBytes != null) {
      final multipartFile = http.MultipartFile.fromBytes(
        'office_image',
        imageBytes,
        filename: 'uploaded_image.jpg',
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    final Map<String, dynamic> result = json.decode(responseBody);

    if (response.statusCode != 200) {
      throw Exception(result['message'] ?? 'فشل الحفظ');
    }
  }

  // حذف مكتب من القائمة النشطة
  Future<void> deleteOfficeStatus(
    String officeName,
    String shift,
    String userId,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/office/status/$officeName/$shift'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId}),
    );
    if (response.statusCode != 200) {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'فشل الحذف');
    }
  }

  // رفع صورة مكتب (اختياري)
  Future<String> uploadOfficeImage(Uint8List imageBytes) async {
    final uri = Uri.parse('$baseUrl/office/upload_image');
    final request = http.MultipartRequest('POST', uri);
    final multipartFile = http.MultipartFile.fromBytes(
      'office_image',
      imageBytes,
      filename: 'uploaded_image.jpg',
      contentType: MediaType('image', 'jpeg'),
    );
    request.files.add(multipartFile);
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    final Map<String, dynamic> result = json.decode(responseBody);
    if (response.statusCode == 200 && result['success'] == true) {
      return result['image_url'];
    } else {
      throw Exception(result['message'] ?? 'فشل رفع الصورة');
    }
  }
}
