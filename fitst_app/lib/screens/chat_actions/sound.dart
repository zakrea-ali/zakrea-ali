// screens/chat_actions/VoiceRecorderPage.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class VoiceRecorderPage extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  final IO.Socket socket;
  final String baseUrl;

  const VoiceRecorderPage({
    Key? key,
    required this.chatId,
    required this.currentUserId,
    required this.socket,
    required this.baseUrl,
  }) : super(key: key);

  @override
  State<VoiceRecorderPage> createState() => _VoiceRecorderPageState();
}

class _VoiceRecorderPageState extends State<VoiceRecorderPage>
    with SingleTickerProviderStateMixin {
  FlutterSoundRecorder? _recorder;
  AudioPlayer? _player;

  bool _isRecording = false;
  bool _isRecorderInitialized = false;
  Duration _recordDuration = Duration.zero;
  Timer? _timer;
  String? _lastRecordedFilePath;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  double _dragOffset = 0;
  bool _isDraggingToCancel = false;
  Offset _dragStartPosition = Offset.zero;

  List<double> _audioLevels = List.filled(30, 0.0);
  Timer? _levelTimer;
  DateTime? _recordingStartTime;

  @override
  void initState() {
    super.initState();
    _initRecorder();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initRecorder() async {
    try {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _player = AudioPlayer();
      _isRecorderInitialized = true;
    } catch (e) {
      // تجاهل
    }
  }

  Future<bool> _requestPermission() async {
    var status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String> _getFilePath(String fileName) async {
    final directory = await getTemporaryDirectory();
    return '${directory.path}/$fileName';
  }

  void _startRecording() async {
    try {
      if (!await _requestPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("الرجاء السماح بالوصول إلى الميكروفون"),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      if (_isRecording) return;

      HapticFeedback.mediumImpact();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'voice_$timestamp.aac';
      final filePath = await _getFilePath(fileName);
      _lastRecordedFilePath = filePath;

      await _recorder!.startRecorder(
        toFile: filePath,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
      );

      setState(() {
        _isRecording = true;
        _recordDuration = Duration.zero;
        _recordingStartTime = DateTime.now();
        _dragOffset = 0;
        _isDraggingToCancel = false;
      });

      _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_isRecording && _recordingStartTime != null && mounted) {
          setState(() {
            _recordDuration = DateTime.now().difference(_recordingStartTime!);
          });
        }
      });

      _startAudioLevelSimulation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("فشل بدء التسجيل: ${e.toString()}")),
        );
      }
    }
  }

  void _startAudioLevelSimulation() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (_isRecording && mounted) {
        setState(() {
          for (int i = 0; i < _audioLevels.length; i++) {
            double randomValue = 0.2 + (Random().nextDouble() * 0.8);
            double waveEffect = (i / _audioLevels.length) * 0.3;
            _audioLevels[i] = (randomValue + waveEffect).clamp(0.1, 1.0);
          }
        });
      }
    });
  }

  Future<void> _stopRecording({bool isCanceled = false}) async {
    if (!_isRecording) return;

    _timer?.cancel();
    _levelTimer?.cancel();
    _pulseController.stop();

    try {
      await _recorder?.stopRecorder();

      setState(() {
        _isRecording = false;
        _recordingStartTime = null;
      });

      HapticFeedback.lightImpact();

      if (!isCanceled && _recordDuration.inSeconds >= 1) {
        if (mounted && _lastRecordedFilePath != null) {
          _showWhatsAppPreview(_lastRecordedFilePath!);
        }
      } else if (_recordDuration.inSeconds < 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("التسجيل قصير جداً"),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1),
            ),
          );
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.pop(context);
          });
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _showWhatsAppPreview(String filePath) {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _WhatsAppVoicePreviewSheet(
        filePath: filePath,
        duration: _recordDuration,
        onSend: () => _uploadAndSendVoice(filePath),
        onCancel: () {
          _deleteRecordedFile(filePath);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _deleteRecordedFile(String filePath) {
    try {
      final file = File(filePath);
      if (file.existsSync()) file.delete();
    } catch (_) {}
  }

  Future<void> _uploadAndSendVoice(String filePath) async {
    Navigator.pop(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                "جاري الإرسال...",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      http.MultipartRequest request = http.MultipartRequest(
        'POST',
        Uri.parse("${widget.baseUrl}/chat/upload_voice"),
      );

      if (await File(filePath).exists()) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'chat_file',
            filePath,
            contentType: MediaType('audio', 'aac'),
          ),
        );
      } else {
        throw Exception("ملف الصوت غير موجود");
      }

      request.fields['chat_id'] = widget.chatId;
      request.fields['sender_id'] = widget.currentUserId;
      request.fields['duration'] = _recordDuration.inSeconds.toString();

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        String fileName = responseData['url'] ??
            responseData['file_name'] ??
            responseData['path'];

        _deleteRecordedFile(filePath);

        if (responseData['message'] != null) {
          widget.socket.emit("message", responseData['message']);
        } else {
          var messageData = {
            "chat_id": widget.chatId,
            "sender_id": widget.currentUserId,
            "message": fileName,
            "type": "voice",
            "duration": _recordDuration.inSeconds,
            "created_at": DateTime.now().toIso8601String(),
          };
          widget.socket.emit("message", messageData);
        }

        if (mounted) {
          Navigator.pop(context);
          Navigator.pop(context);
        }
      } else {
        throw Exception("Upload failed with status: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("فشل إرسال الرسالة الصوتية: ${e.toString()}"),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _dragStartPosition = details.globalPosition;
    _startRecording();
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isRecording) return;
    final dx = details.globalPosition.dx - _dragStartPosition.dx;
    setState(() {
      if (dx < -50) {
        _isDraggingToCancel = true;
        _dragOffset = dx.clamp(-150, 0);
      } else {
        _isDraggingToCancel = false;
        _dragOffset = 0;
      }
    });
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_isDraggingToCancel) {
      _stopRecording(isCanceled: true);
    } else {
      _stopRecording(isCanceled: false);
    }
    setState(() {
      _dragOffset = 0;
      _isDraggingToCancel = false;
    });
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.remainder(60);
    final minutes = duration.inMinutes.remainder(60);
    if (minutes > 0) return "$minutes:${seconds.toString().padLeft(2, '0')}";
    return "0:$seconds";
  }

  @override
  void dispose() {
    _timer?.cancel();
    _levelTimer?.cancel();
    _pulseController.dispose();
    _recorder?.closeRecorder();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [colorScheme.primary.withOpacity(0.2), Colors.black]
                      : [
                          colorScheme.primary.withOpacity(0.1),
                          colorScheme.background,
                        ],
                ),
              ),
            ),
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: AnimatedOpacity(
                    opacity: _isRecording ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          transform: Matrix4.translationValues(
                            _dragOffset,
                            0,
                            0,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.arrow_back,
                                color: _isDraggingToCancel
                                    ? Colors.red
                                    : colorScheme.onSurface.withOpacity(0.54),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isDraggingToCancel
                                    ? "حرر للإلغاء"
                                    : "اسحب للإلغاء",
                                style: TextStyle(
                                  color: _isDraggingToCancel
                                      ? Colors.red
                                      : colorScheme.onSurface.withOpacity(0.54),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (_isRecording)
                  Container(
                    height: 80,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(
                        _audioLevels.length,
                        (index) => Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 50),
                            height: 20 + (_audioLevels[index] * 60),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    _formatDuration(_recordDuration),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 48,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: GestureDetector(
                    onLongPressStart: _handleLongPressStart,
                    onLongPressMoveUpdate: _handleLongPressMoveUpdate,
                    onLongPressEnd: _handleLongPressEnd,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _isRecording ? _pulseAnimation.value : 1.0,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isDraggingToCancel
                                  ? Colors.red
                                  : colorScheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isDraggingToCancel
                                          ? Colors.red
                                          : colorScheme.primary)
                                      .withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: _isRecording ? 8 : 0,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.mic,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                AnimatedOpacity(
                  opacity: _isRecording ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _isDraggingToCancel
                        ? "حرر لإلغاء التسجيل"
                        : "حرر لإرسال التسجيل",
                    style: TextStyle(
                      color: _isDraggingToCancel
                          ? Colors.red
                          : colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== نافذة معاينة الصوت (باستخدام just_audio) ====================
class _WhatsAppVoicePreviewSheet extends StatefulWidget {
  final String filePath;
  final Duration duration;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const _WhatsAppVoicePreviewSheet({
    required this.filePath,
    required this.duration,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<_WhatsAppVoicePreviewSheet> createState() =>
      _WhatsAppVoicePreviewSheetState();
}

class _WhatsAppVoicePreviewSheetState
    extends State<_WhatsAppVoicePreviewSheet> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Timer? _timer;
  double _sliderValue = 0.0;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<dynamic>? _playerStateSubscription; // ✅ استخدم dynamic

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    _positionSubscription = _player?.positionStream.listen((Duration p) {
      if (mounted) {
        setState(() {
          _position = p;
          _sliderValue = widget.duration.inMilliseconds > 0
              ? p.inMilliseconds / widget.duration.inMilliseconds
              : 0.0;
        });
      }
    });

    _playerStateSubscription = _player?.playerStateStream.listen((state) {
      if (mounted) {
        // تحقق من حالة المشغل
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
            _sliderValue = 0.0;
          });
          _timer?.cancel();
        }
        if (state.playing != _isPlaying) {
          setState(() {
            _isPlaying = state.playing;
          });
        }
      }
    });
  }

  void _togglePlayback() async {
    if (_player == null) return;

    if (_isPlaying) {
      await _player?.pause();
      setState(() {
        _isPlaying = false;
      });
      _timer?.cancel();
    } else {
      try {
        await _player?.setFilePath(widget.filePath);
        await _player?.play();
        setState(() {
          _isPlaying = true;
        });
        _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (_isPlaying && mounted) {
            // التحديث عبر positionStream
          }
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("تعذر تشغيل الصوت: $e")));
        }
      }
    }
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.remainder(60);
    final minutes = duration.inMinutes.remainder(60);
    if (minutes > 0) return "$minutes:${seconds.toString().padLeft(2, '0')}";
    return "0:$seconds";
  }

  double _getWaveHeight(int index) {
    if (!_isPlaying) return 0.3;
    final phase = DateTime.now().millisecondsSinceEpoch / 200;
    final sinValue = sin(phase + (index * 0.2));
    return 0.2 + (sinValue.abs() * 0.6);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 60,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(
                    40,
                    (index) => Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 20 + (_getWaveHeight(index) * 40),
                      decoration: BoxDecoration(
                        color: _isPlaying
                            ? colorScheme.primary
                            : (isDark ? Colors.grey[400] : Colors.grey[500]),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  activeTrackColor: colorScheme.primary,
                  inactiveTrackColor:
                      isDark ? Colors.grey[800] : Colors.grey[300],
                  thumbColor: colorScheme.primary,
                ),
                child: Slider(
                  value: _sliderValue.clamp(0.0, 1.0),
                  onChanged: (value) async {
                    final newPosition = Duration(
                      milliseconds:
                          (value * widget.duration.inMilliseconds).round(),
                    );
                    setState(() {
                      _sliderValue = value;
                      _position = newPosition;
                    });
                    await _player?.seek(newPosition);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDuration(widget.duration),
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _togglePlayback,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: widget.onCancel,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.red.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        "إلغاء",
                        style: TextStyle(color: Colors.red, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.onSend,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            "إرسال",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}