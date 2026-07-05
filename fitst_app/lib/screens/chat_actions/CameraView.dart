import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class CameraViewPage extends StatefulWidget {
  final Uint8List bytes;

  const CameraViewPage({Key? key, required this.bytes}) : super(key: key);

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

class _CameraViewPageState extends State<CameraViewPage> {
  final TextEditingController _captionController = TextEditingController();
  bool _isLoading = false;
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.bytes;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _uploadToServer() async {
    if (_imageBytes == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
      // ✅ استخدام ApiConfig.baseUrl بدلاً من الـ IP الثابت
      final String baseUrl = ApiConfig.baseUrl;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse("$baseUrl/camera/upload"),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'camera_file',
          _imageBytes!,
          filename: "cam_${DateTime.now().millisecondsSinceEpoch}.jpg",
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        Navigator.pop(context, {
          "url": responseData['url'],
          "caption": _captionController.text.trim(),
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ في السيرفر: ${response.statusCode}")),
        );
      }
    } catch (e) {
      debugPrint("Upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("حدث خطأ أثناء الرفع")));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.crop_rotate, size: 27),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined, size: 27),
            onPressed: () {},
          ),
          IconButton(icon: const Icon(Icons.title, size: 27), onPressed: () {}),
          IconButton(icon: const Icon(Icons.edit, size: 27), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _imageBytes == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : InteractiveViewer(
                    child: Image.memory(
                      _imageBytes!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
          ),
          Container(
            color: Colors.black38,
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
            child: SafeArea(
              top: false,
              child: TextFormField(
                controller: _captionController,
                style: const TextStyle(color: Colors.white, fontSize: 17),
                maxLines: 6,
                minLines: 1,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: "أضف تعليقاً...",
                  hintStyle: const TextStyle(
                    color: Colors.white70,
                    fontSize: 17,
                  ),
                  prefixIcon: const Icon(
                    Icons.add_photo_alternate,
                    color: Colors.white,
                    size: 27,
                  ),
                  suffixIcon: GestureDetector(
                    onTap: _isLoading ? null : _uploadToServer,
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: const Color(0xFF128C7E),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 27,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
