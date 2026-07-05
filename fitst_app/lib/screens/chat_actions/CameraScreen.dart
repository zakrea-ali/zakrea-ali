import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:fitst_app/screens/chat_actions/VideoView.dart';
import 'package:path_provider/path_provider.dart';

// قائمة الكاميرات المتاحة (يتم تعبئتها قبل تشغيل التطبيق)
List<CameraDescription> cameras = [];

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    Key? key,
    required this.chatId,
    required this.currentUserId,
    required this.socket,
    this.onVideoSent,
  }) : super(key: key);

  final String chatId;
  final String currentUserId;
  final IO.Socket socket;
  final Function(Map<String, dynamic>)? onVideoSent;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Future<void>? _cameraValue;
  bool _isFront = false;
  bool _isFlashOn = false;
  bool _isRecording = false;
  double _transformAngle = 0;

  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;

  // إعدادات التسجيل
  static const Duration _minRecordDuration = Duration(seconds: 1);
  static const Duration _maxRecordDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionsAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCameras();
    }
  }

  Future<void> _checkPermissionsAndInit() async {
    if (kIsWeb) {
      await _setupCameras();
      return;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      await _setupCameras();
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("الصلاحيات مطلوبة"),
        content: const Text(
          "يحتاج التطبيق للوصول للكاميرا والميكروفون لتتمكن من التقاط الصور والفيديو.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => openAppSettings(),
            child: const Text("الإعدادات"),
          ),
        ],
      ),
    );
  }

  Future<void> _setupCameras() async {
    try {
      if (cameras.isEmpty) {
        cameras = await availableCameras();
      }
      if (cameras.isNotEmpty) {
        CameraDescription selectedCamera = cameras.firstWhere(
          (cam) => _isFront
              ? cam.lensDirection == CameraLensDirection.front
              : cam.lensDirection == CameraLensDirection.back,
          orElse: () => cameras[0],
        );
        await _initCamera(selectedCamera);
      }
    } catch (e) {
      debugPrint("Error setting up cameras: $e");
    }
  }

  Future<void> _initCamera(CameraDescription camera) async {
    await _cameraController?.dispose();
    _cameraController = CameraController(
      camera,
      kIsWeb ? ResolutionPreset.medium : ResolutionPreset.veryHigh,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _cameraValue = _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
    setState(() {});
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isFront) {
      return;
    }
    try {
      final newFlashMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
      await _cameraController!.setFlashMode(newFlashMode);
      setState(() => _isFlashOn = !_isFlashOn);
      if (!kIsWeb) HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint("Flash Error: $e");
    }
  }

  Future<void> _takePhoto() async {
    if (!mounted) return; // ✅ التحقق من mounted
    if (_isRecording) return;
    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return;
      }
      if (!kIsWeb) HapticFeedback.mediumImpact();
      final XFile file = await _cameraController!.takePicture();
      final Uint8List bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.pop(context, bytes);
    } catch (e) {
      debugPrint("Capture Error: $e");
    }
  }

  void _startVideoRecording() async {
    if (!mounted) return; // ✅ التحقق من mounted
    if (_isRecording) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      await _cameraController!.startVideoRecording();
      if (!kIsWeb) HapticFeedback.heavyImpact();
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
          if (_recordingDuration >= _maxRecordDuration) {
            timer.cancel();
            _stopVideoRecording();
          }
        }
      });
    } catch (e) {
      debugPrint("Start Recording Error: $e");
    }
  }

  void _stopVideoRecording() async {
    if (!mounted) return; // ✅ التحقق من mounted
    if (!_isRecording) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      _recordingTimer?.cancel();
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      setState(() => _isRecording = false);

      if (_recordingDuration < _minRecordDuration) {
        if (!kIsWeb) {
          final file = File(videoFile.path);
          if (await file.exists()) await file.delete();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "⚠️ اضغط لفترة أطول لتسجيل الفيديو (ثانية على الأقل)",
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (videoFile.path.isNotEmpty && mounted) {
        final String permanentPath = await _saveVideoPermanently(
          videoFile.path,
        );
        if (mounted) {
          if (!kIsWeb) HapticFeedback.lightImpact();
          await Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VideoViewPage(
                path: permanentPath,
                chatId: widget.chatId,
                currentUserId: widget.currentUserId,
                socket: widget.socket,
                onVideoSent: widget.onVideoSent ?? (_) {},
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Stop Recording Error: $e");
      setState(() => _isRecording = false);
    }
  }

  Future<String> _saveVideoPermanently(String tempPath) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = "video_${DateTime.now().millisecondsSinceEpoch}.mp4";
      final permanentPath = "${directory.path}/$fileName";
      final File tempFile = File(tempPath);
      await tempFile.copy(permanentPath);
      await tempFile.delete();
      return permanentPath;
    } catch (e) {
      debugPrint("Error saving video permanently: $e");
      return tempPath;
    }
  }

  Future<void> _switchCamera() async {
    if (_isFlashOn) {
      await _cameraController?.setFlashMode(FlashMode.off);
    }
    setState(() {
      _isFront = !_isFront;
      _transformAngle += pi;
      _isFlashOn = false;
    });
    await _setupCameras();
    if (!kIsWeb) HapticFeedback.selectionClick();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // معاينة الكاميرا
          FutureBuilder(
            future: _cameraValue,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  _cameraController != null &&
                  _cameraController!.value.isInitialized) {
                return Positioned.fill(
                  child: CameraPreview(_cameraController!),
                );
              }
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
          ),

          // مؤقت التسجيل العلوي
          if (_isRecording)
            Positioned(
              top: 60,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.red, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(_recordingDuration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "تسجيل",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // زر الإغلاق
          Positioned(
            top: 60,
            left: 20,
            child: SafeArea(
              bottom: false,
              child: GestureDetector(
                onTap: () {
                  if (_isRecording) _stopVideoRecording();
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),

          // شريط التحكم السفلي
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 25),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // زر الفلاش
                        GestureDetector(
                          onTap: _toggleFlash,
                          child: AnimatedOpacity(
                            opacity: _isFront ? 0.4 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isFlashOn
                                    ? const Color(0xFF075E54)
                                    : Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isFlashOn ? Icons.flash_on : Icons.flash_off,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),

                        // 🔹 زر التصوير/التسجيل (تم استبدال InkWell بـ GestureDetector)
                        GestureDetector(
                          onTap: _takePhoto,
                          onLongPress: _startVideoRecording,
                          onLongPressEnd: (details) {
                            _stopVideoRecording();
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // الدائرة الخارجية
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 50),
                                width: _isRecording ? 85 : 80,
                                height: _isRecording ? 85 : 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isRecording
                                      ? Colors.red.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.2),
                                ),
                              ),
                              // الزر الداخلي
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                width: _isRecording ? 65 : 75,
                                height: _isRecording ? 65 : 75,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  color: _isRecording
                                      ? Colors.red
                                      : Colors.white.withOpacity(0.3),
                                ),
                                child: Center(
                                  child: _isRecording
                                      ? AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.camera_alt,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // زر تبديل الكاميرا
                        GestureDetector(
                          onTap: _switchCamera,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Transform.rotate(
                              angle: _transformAngle,
                              child: const Icon(
                                Icons.flip_camera_ios,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // النص التعليمي
                    AnimatedOpacity(
                      opacity: _isRecording ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Column(
                        children: [
                          const Text(
                            "📸 اضغط لالتقاط صورة",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.touch_app,
                                  size: 14,
                                  color: Colors.white70,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "اضغط مطولاً لتسجيل فيديو",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isRecording)
                      Column(
                        children: [
                          Text(
                            "✋ ارفع إصبعك لإيقاف التسجيل",
                            style: TextStyle(
                              color: Colors.red[300],
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "الحد الأقصى ${_formatDuration(_maxRecordDuration)}",
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
