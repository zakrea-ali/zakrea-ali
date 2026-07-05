import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class VideoViewPage extends StatefulWidget {
  const VideoViewPage({
    Key? key,
    required this.path,
    required this.chatId,
    required this.currentUserId,
    required this.socket,
    required this.onVideoSent,
  }) : super(key: key);

  final String path;
  final String chatId;
  final String currentUserId;
  final IO.Socket socket;
  final Function(Map<String, dynamic>) onVideoSent;

  @override
  State<VideoViewPage> createState() => _VideoViewPageState();
}

class _VideoViewPageState extends State<VideoViewPage> {
  VideoPlayerController? _controller;
  final TextEditingController _captionController = TextEditingController();

  bool _isLoading = false;
  bool _initFailed = false;
  bool _videoReady = false;

  // ✅ استخدام ApiConfig.baseUrl بدلاً من الـ IP الثابت
  String get serverUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      debugPrint("Initializing video from path: ${widget.path}");

      if (kIsWeb) {
        final uri = Uri.tryParse(widget.path);
        if (uri == null) {
          debugPrint("Invalid URI for web");
          setState(() => _initFailed = true);
          return;
        }
        _controller = VideoPlayerController.networkUrl(uri);
      } else {
        final file = File(widget.path);
        if (!await file.exists()) {
          debugPrint("Video file does not exist: ${widget.path}");
          setState(() => _initFailed = true);
          return;
        }
        _controller = VideoPlayerController.file(file);
      }

      await _controller!.initialize();

      if (!mounted) return;

      debugPrint(
        "Video initialized successfully. Duration: ${_controller!.value.duration}",
      );

      setState(() {
        _videoReady = true;
      });

      _controller!
        ..setLooping(true)
        ..play();
    } catch (e) {
      debugPrint("VIDEO INIT ERROR: $e");
      if (mounted) {
        setState(() {
          _initFailed = true;
        });
      }
    }
  }

  Future<void> _handleSend() async {
    if (!mounted || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      debugPrint("Starting video upload to: $serverUrl/camera/upload");

      final request = http.MultipartRequest(
        'POST',
        Uri.parse("$serverUrl/camera/upload"),
      );

      String fileName = "video_${DateTime.now().millisecondsSinceEpoch}.mp4";

      if (kIsWeb) {
        final response = await http.get(Uri.parse(widget.path));
        final bytes = response.bodyBytes;

        debugPrint(
          "Uploading web video: $fileName, size: ${bytes.length} bytes",
        );

        request.files.add(
          http.MultipartFile.fromBytes(
            'camera_file',
            bytes,
            filename: fileName,
            contentType: MediaType('video', 'mp4'),
          ),
        );
      } else {
        debugPrint("Uploading mobile video: $fileName, path: ${widget.path}");

        request.files.add(
          await http.MultipartFile.fromPath(
            'camera_file',
            widget.path,
            filename: fileName,
            contentType: MediaType('video', 'mp4'),
          ),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint("Upload response status: ${response.statusCode}");
      debugPrint("Upload response body: ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint("Server returned: $data");

        String videoFileName = data['url'];
        String caption = _captionController.text.trim();

        if (!mounted) return;

        // 🔥 انتظر 2 ثانية للتأكد من أن الفيديو جاهز على السيرفر
        debugPrint("⏳ Waiting for video to be ready on server...");
        await Future.delayed(const Duration(seconds: 2));

        // 🔥 التحقق من أن الفيديو جاهز (محاولة تحميله)
        final fullUrl = "$serverUrl/uploads_camera/$videoFileName";
        debugPrint("🔍 Verifying video URL: $fullUrl");

        // محاولة التحقق من وجود الفيديو
        bool isVideoReady = await _checkVideoReady(fullUrl);
        if (!isVideoReady) {
          debugPrint("⚠️ Video not ready yet, waiting additional 1 second...");
          await Future.delayed(const Duration(seconds: 1));
        }

        // إنشاء معرف فريد للرسالة
        final messageId = "temp_${DateTime.now().millisecondsSinceEpoch}";

        // 🔥 إنشاء رسالة مؤقتة للإضافة المحلية
        final temporaryMessage = {
          "id": messageId,
          "chat_id": widget.chatId,
          "sender_id": widget.currentUserId,
          "message": videoFileName,
          "created_at": DateTime.now().toIso8601String(),
          "caption": caption,
        };

        // 🔥 إضافة الرسالة محلياً عبر دالة رد الاتصال (هذه ستظهرها فوراً)
        widget.onVideoSent(temporaryMessage);

        // 🔥 إرسال رسالة الفيديو عبر السوكيت للسيرفر
        final messageData = {
          "chat_id": widget.chatId,
          "sender_id": widget.currentUserId,
          "message": videoFileName,
        };

        debugPrint("Sending video message: $messageData");

        // إرسال عبر السوكيت مع تأكيد الاستلام
        widget.socket.emitWithAck(
          "message",
          messageData,
          ack: (data) {
            debugPrint("Message acknowledged by server: $data");
          },
        );

        // إظهار رسالة نجاح
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ تم إرسال الفيديو بنجاح"),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );

        // تأخير بسيط قبل العودة
        await Future.delayed(const Duration(milliseconds: 300));

        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        throw "Server Error: ${response.statusCode} - ${response.body}";
      }
    } catch (e) {
      debugPrint("UPLOAD ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ فشل رفع الفيديو: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🔥 دالة للتحقق من أن الفيديو جاهز على السيرفر
  Future<bool> _checkVideoReady(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Check video ready error: $e");
      return false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _initFailed
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 60,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "فشل تحميل الفيديو للمعاينة",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "مسار الفيديو: ${widget.path}",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF075E54),
                        ),
                        child: const Text("رجوع"),
                      ),
                    ],
                  )
                : !_videoReady
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            "جاري تحميل الفيديو...",
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_controller!.value.isPlaying) {
                              _controller!.pause();
                            } else {
                              _controller!.play();
                            }
                          });
                        },
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
          ),
          // زر الإغلاق
          Positioned(
            top: 40,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
          // شريط الإرسال
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              width: MediaQuery.of(context).size.width,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: "أضف وصفاً للفيديو...",
                          hintStyle: const TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _isLoading ? null : _handleSend,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF075E54),
                        shape: BoxShape.circle,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // مؤشر التسجيل
          if (_videoReady)
            Positioned(
              top: 40,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(_controller!.value.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}
