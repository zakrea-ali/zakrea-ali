import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:fitst_app/screens/SelectMembers.dart';
import 'package:fitst_app/screens/chat_actions/location_picker_page.dart';
import 'package:fitst_app/screens/chat_actions/CameraScreen.dart';
import 'package:fitst_app/screens/chat_actions/video_player_widget.dart';
import 'package:fitst_app/screens/chat_actions/UniversalAudioPlayer.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:flutter_sound/flutter_sound.dart'; // ✅ استبدال record بـ flutter_sound
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fitst_app/Pages/ChatPageForForward.dart';

// ==================== VideoPlayerManager (بدون تغيير) ====================
class VideoPlayerManager {
  static final VideoPlayerManager _instance = VideoPlayerManager._internal();
  factory VideoPlayerManager() => _instance;
  VideoPlayerManager._internal();
  VideoPlayerController? _currentController;
  String? _currentVideoId;
  void playVideo(VideoPlayerController controller, String videoId) {
    if (_currentController != null && _currentController != controller) {
      _currentController!.pause();
    }
    _currentController = controller;
    _currentVideoId = videoId;
    controller.play();
  }

  void stopAllVideos() {
    if (_currentController != null) {
      _currentController!.pause();
      _currentController = null;
      _currentVideoId = null;
    }
  }
}

// ============================================================
//  Custom Message Input Widget - معدل لاستخدام flutter_sound
// ============================================================
class _CustomMessageInput extends StatefulWidget {
  final bool isChatLocked;
  final bool isAdmin;
  final VoidCallback onSendTextMessage;
  final VoidCallback onAttachPressed;
  final VoidCallback onCameraPressed;
  final TextEditingController controller;
  final String currentGroupId;
  final String currentUserId;
  final String baseUrl;
  final IO.Socket socket;
  final Function(Map<String, dynamic>) onNewMessage;

  const _CustomMessageInput({
    Key? key,
    required this.isChatLocked,
    required this.isAdmin,
    required this.onSendTextMessage,
    required this.onAttachPressed,
    required this.onCameraPressed,
    required this.controller,
    required this.currentGroupId,
    required this.currentUserId,
    required this.baseUrl,
    required this.socket,
    required this.onNewMessage,
  }) : super(key: key);

  @override
  State<_CustomMessageInput> createState() => _CustomMessageInputState();
}

class _CustomMessageInputState extends State<_CustomMessageInput> {
  final ValueNotifier<bool> _showSendButtonNotifier = ValueNotifier(false);
  bool _isRecordingVoice = false;
  bool _isVoiceLocked = false;
  bool _isSwipedToCancel = false;
  bool _isSwipedToLock = false;
  Offset _dragStartPosition = Offset.zero;
  FlutterSoundRecorder? _voiceRecorder; // ✅ تغيير النوع
  Duration _voiceDuration = Duration.zero;
  Timer? _voiceTimer;
  DateTime? _voiceStartTime;
  String? _currentVoicePath;
  final ValueNotifier<List<double>> _voiceWaveLevels = ValueNotifier(
    List.filled(40, 0.0),
  );
  Timer? _waveTimer;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    widget.controller.addListener(_onTextChanged);
    _onTextChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _voiceRecorder?.closeRecorder(); // ✅ إغلاق المسجل
    _voiceTimer?.cancel();
    _waveTimer?.cancel();
    _voiceWaveLevels.dispose();
    _showSendButtonNotifier.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _showSendButtonNotifier.value = widget.controller.text.trim().isNotEmpty;
  }

  Future<void> _initRecorder() async {
    _voiceRecorder = FlutterSoundRecorder();
    await _voiceRecorder?.openRecorder(); // ✅ فتح المسجل
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Future<void> _startVoiceRecording() async {
    try {
      // ✅ طلب إذن الميكروفون (Android)
      var status = await Permission.microphone.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("الرجاء السماح بالوصول إلى الميكروفون"),
          ),
        );
        return;
      }

      HapticFeedback.mediumImpact();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'voice_$timestamp.aac'; // ✅ تنسيق aac
      final directory = await getTemporaryDirectory();
      _currentVoicePath = '${directory.path}/$fileName';

      // ✅ بدء التسجيل باستخدام flutter_sound
      await _voiceRecorder!.startRecorder(
        toFile: _currentVoicePath!,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
      );

      setState(() {
        _isRecordingVoice = true;
        _voiceDuration = Duration.zero;
        _voiceStartTime = DateTime.now();
        _isVoiceLocked = false;
        _isSwipedToCancel = false;
        _isSwipedToLock = false;
      });

      _voiceTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_isRecordingVoice && _voiceStartTime != null && mounted) {
          setState(() {
            _voiceDuration = DateTime.now().difference(_voiceStartTime!);
          });
        }
      });

      _startWaveSimulation();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("حدث خطأ أثناء بدء التسجيل: $e")),
      );
    }
  }

  void _startWaveSimulation() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (_isRecordingVoice && mounted) {
        final newLevels = List<double>.from(_voiceWaveLevels.value);
        for (int i = 0; i < newLevels.length; i++) {
          double randomValue =
              0.2 + (DateTime.now().millisecondsSinceEpoch % 600) / 800;
          double waveEffect = (i / newLevels.length) * 0.4;
          newLevels[i] = (randomValue + waveEffect).clamp(0.1, 1.0);
        }
        _voiceWaveLevels.value = newLevels;
      }
    });
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    if (!_isRecordingVoice) return;
    _voiceTimer?.cancel();
    _waveTimer?.cancel();
    try {
      await _voiceRecorder?.stopRecorder(); // ✅ إيقاف التسجيل
      setState(() {
        _isRecordingVoice = false;
        _isVoiceLocked = false;
        _isSwipedToCancel = false;
        _isSwipedToLock = false;
        _voiceStartTime = null;
      });
      HapticFeedback.lightImpact();
      if (_voiceDuration.inSeconds >= 1) {
        await _sendVoiceMessage();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("التسجيل قصير جداً")));
        _deleteVoiceFile();
      }
    } catch (e) {
      _deleteVoiceFile();
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceTimer?.cancel();
    _waveTimer?.cancel();
    try {
      await _voiceRecorder?.stopRecorder();
    } catch (_) {}
    setState(() {
      _isRecordingVoice = false;
      _isVoiceLocked = false;
      _isSwipedToCancel = false;
      _isSwipedToLock = false;
      _voiceStartTime = null;
    });
    _deleteVoiceFile();
    HapticFeedback.lightImpact();
  }

  void _deleteVoiceFile() async {
    if (_currentVoicePath != null) {
      try {
        final file = File(_currentVoicePath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _currentVoicePath = null;
  }

  Future<void> _sendVoiceMessage() async {
    if (_currentVoicePath == null) return;
    try {
      final url = Uri.parse("${widget.baseUrl}/chat/upload_voice");
      http.MultipartRequest request = http.MultipartRequest('POST', url);
      final file = File(_currentVoicePath!);
      if (await file.exists()) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'chat_file',
            _currentVoicePath!,
            contentType: MediaType('audio', 'aac'), // ✅ تنسيق aac
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("الملف الصوتي غير موجود")),
        );
        return;
      }

      request.fields['chat_id'] = widget.currentGroupId;
      request.fields['sender_id'] = widget.currentUserId;
      request.fields['duration'] = _voiceDuration.inSeconds.toString();

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        String rawFileName =
            responseData['url'] ?? responseData['message']?['message'] ?? "";
        String fileName = rawFileName.contains('/')
            ? rawFileName.split('/').last
            : rawFileName;
        _deleteVoiceFile();
        var messageData = {
          "chat_id": widget.currentGroupId,
          "sender_id": widget.currentUserId,
          "message": fileName,
          "type": "voice",
          "duration": _voiceDuration.inSeconds,
          "chat_type": "group",
          "created_at": DateTime.now().toIso8601String(),
          "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
        };
        widget.socket.emit("message", messageData);
        widget.onNewMessage(messageData);
      } else {
        throw Exception("Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("فشل إرسال الصوت: $e")));
    }
  }

  Widget _buildPulseDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (_, value, __) => Opacity(
        opacity: value,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        ),
      ),
      onEnd: () => setState(() {}),
    );
  }

  Widget _buildVoiceRecorderWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5);
    final textColor = isDark ? Colors.white : Colors.black87;
    const primaryBlueColor = Colors.blue;

    if (_isVoiceLocked) {
      return Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.lock, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Text(
              _formatDuration(_voiceDuration),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () async => await _stopVoiceRecordingAndSend(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: primaryBlueColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.send, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text("إرسال", style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.grey,
                size: 26,
              ),
              onPressed: () async => await _cancelVoiceRecording(),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.grey,
              size: 26,
            ),
            onPressed: () async => await _cancelVoiceRecording(),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_voiceDuration),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(width: 4),
          _buildPulseDot(),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: ValueListenableBuilder<List<double>>(
                  valueListenable: _voiceWaveLevels,
                  builder: (context, levels, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(levels.length, (i) {
                        double height = 4 + (levels[i] * 24);
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 60),
                          width: 3,
                          height: height,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: i % 2 == 0
                                ? Colors.grey[400]
                                : Colors.grey[600],
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: primaryBlueColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.lock_open, size: 16, color: primaryBlueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFieldBackgroundColor =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5);
    final borderColor = isDark ? Colors.grey[800] : Colors.grey[300];
    final iconColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white : Colors.black87;

    if (widget.isChatLocked && !widget.isAdmin) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: isDark ? Colors.black87 : Colors.white,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: textFieldBackgroundColor,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: borderColor!, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: iconColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "المجموعة مقفلة، فقط المشرفون يمكنهم الإرسال",
                      style: TextStyle(color: iconColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _smartButton() {
      return ValueListenableBuilder<bool>(
        valueListenable: _showSendButtonNotifier,
        builder: (context, showSend, child) {
          if (showSend) {
            return GestureDetector(
              onTap: () {
                widget.onSendTextMessage();
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 24),
              ),
            );
          } else {
            return GestureDetector(
              onLongPressStart: (d) {
                if (!_isRecordingVoice && !_isVoiceLocked) {
                  _dragStartPosition = d.localPosition;
                  _startVoiceRecording();
                }
              },
              onLongPressMoveUpdate: (d) {
                if (_isRecordingVoice && !_isVoiceLocked) {
                  final dx = d.localPosition.dx - _dragStartPosition.dx;
                  final dy = d.localPosition.dy - _dragStartPosition.dy;
                  setState(() {
                    _isSwipedToCancel = dx < -50;
                    _isSwipedToLock = dy < -50;
                  });
                }
              },
              onLongPressEnd: (_) async {
                if (_isRecordingVoice && !_isVoiceLocked) {
                  if (_isSwipedToCancel) {
                    await _cancelVoiceRecording();
                  } else if (_isSwipedToLock) {
                    setState(() => _isVoiceLocked = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("🔒 تم قفل التسجيل"),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  } else {
                    await _stopVoiceRecordingAndSend();
                  }
                  if (mounted)
                    setState(() {
                      _isSwipedToCancel = false;
                      _isSwipedToLock = false;
                    });
                }
              },
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("اضغط مطولاً لتسجيل مقطع صوتي"),
                    duration: Duration(milliseconds: 700),
                  ),
                );
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isSwipedToCancel
                      ? Colors.red
                      : (_isSwipedToLock ? Colors.orange : Colors.blue),
                ),
                child: Icon(
                  _isVoiceLocked
                      ? Icons.lock
                      : (_isSwipedToCancel
                          ? Icons.close
                          : (_isSwipedToLock ? Icons.lock_open : Icons.mic)),
                  color: Colors.white,
                  size: 22,
                ),
              ),
            );
          }
        },
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: isDark ? Colors.black87 : Colors.white,
      child: Row(
        children: [
          if (!_isRecordingVoice)
            IconButton(
              icon: Icon(Icons.attach_file, color: iconColor),
              onPressed: widget.onAttachPressed,
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: textFieldBackgroundColor,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: borderColor!, width: 1),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: _isRecordingVoice
                        ? _buildVoiceRecorderWidget()
                        : TextField(
                            controller: widget.controller,
                            maxLines: 5,
                            minLines: 1,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: "اكتب رسالة...",
                              hintStyle: TextStyle(color: hintColor),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!_isRecordingVoice)
            IconButton(
              icon: Icon(Icons.camera_alt, color: iconColor),
              onPressed: widget.onCameraPressed,
            ),
          _smartButton(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildMessageInput();
  }
}

// ============================================================
//  الصفحة الرئيسية للمجموعة (بدون تغيير)
// ============================================================
class CreateGroupPage extends StatefulWidget {
  final String currentUserId;
  final String baseUrl;
  final ChatModel? chatmodel;
  final Map<String, dynamic>? forwardingMessage;
  const CreateGroupPage({
    Key? key,
    required this.currentUserId,
    required this.baseUrl,
    this.chatmodel,
    this.forwardingMessage,
  }) : super(key: key);

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  // ==================== متغيرات عامة ====================
  late bool isCreationMode;
  late IO.Socket socket;
  ChatModel? currentGroup;
  List<ChatModel> selectedMembers = [];
  final TextEditingController _groupNameController = TextEditingController();
  Uint8List? _groupImageBytes;
  bool _isCreating = false;

  // ==================== متغيرات الشات ====================
  List<Map<String, dynamic>> _messages = [];
  late final ValueNotifier<List<Map<String, dynamic>>> _messagesNotifier;
  bool isLoadingMessages = true;
  final TextEditingController _messageController = TextEditingController();
  Set<String> selectedMessageIds = {};
  bool isSelectionMode = false;
  String _selectedAction = '';
  bool _isChatLocked = false;
  bool _hasLoadedMessages = false;
  final Map<String, Future<String?>> _memberAvatarCache = {};

  // ==================== متغيرات التحسين ====================
  bool _isChatReady = false;
  final ScrollController _scrollController = ScrollController();

  // ==================== متغيرات الردود وإعادة التوجيه ====================
  late SharedPreferences _prefs;
  Set<String> _forwardedMessageIds = {};
  Map<String, dynamic>? _replyingToMessage;
  bool get _isReplying => _replyingToMessage != null;
  Offset _currentTapPosition = Offset.zero;

  bool get isAdmin =>
      currentGroup?.createdBy == widget.currentUserId ||
      currentGroup?.permissions.contains(widget.currentUserId) == true;

  // ==================== دورة الحياة ====================
  @override
  void initState() {
    super.initState();
    isCreationMode = widget.chatmodel == null;
    _messagesNotifier = ValueNotifier(_messages);
    _initSharedPrefs();
    _initializeSocket();
    if (!isCreationMode) {
      currentGroup = widget.chatmodel;
      _loadMessages();
      _listenToGroupMessages();
      _refreshGroupData();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (currentGroup != null) {
          setState(() => _isChatReady = true);
        }
      });
      if (widget.forwardingMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && currentGroup != null) {
              _showForwardConfirmation(widget.forwardingMessage!);
            } else {
              _showCriticalError("خطأ: لم يتم تحميل المجموعة بعد");
            }
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _messageController.dispose();
    _messagesNotifier.dispose();
    _scrollController.dispose();
    socket.disconnect();
    VideoPlayerManager().stopAllVideos();
    super.dispose();
  }

  // ==================== التهيئة والإعداد ====================
  Future<void> _initSharedPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadForwardedIds();
  }

  void _loadForwardedIds() {
    final List<String>? ids = _prefs.getStringList(
      'forwarded_messages_${widget.currentUserId}',
    );
    if (ids != null) {
      _forwardedMessageIds = ids.toSet();
    }
  }

  void _saveForwardedId(String messageId) {
    _forwardedMessageIds.add(messageId);
    _prefs.setStringList(
      'forwarded_messages_${widget.currentUserId}',
      _forwardedMessageIds.toList(),
    );
  }

  String _getMessagePreview(Map<String, dynamic> message) {
    final msgContent = message['message'] ?? '';
    final msgType = message['type'] ?? '';
    final int duration = message['duration'] ?? 0;
    String type = msgType;
    if (type.isEmpty) {
      if (_isImageMessage(msgContent))
        type = 'image';
      else if (_isVideoMessage(msgContent))
        type = 'video';
      else if (_isVoiceMessage(msgContent))
        type = 'voice';
      else if (msgContent.startsWith('LOCATION:'))
        type = 'location';
      else if (_isDocumentMessage(msgContent))
        type = 'document';
      else
        type = 'text';
    }
    switch (type) {
      case 'image':
        return '🖼️ صورة';
      case 'video':
        return '🎥 فيديو';
      case 'voice':
        final durationText = duration > 0
            ? ' (${_formatDuration(Duration(seconds: duration))})'
            : '';
        return '🎤 رسالة صوتية$durationText';
      case 'location':
        return '📍 موقع';
      case 'document':
        final fileName = msgContent.split('/').last;
        return '📄 $fileName';
      default:
        String preview = msgContent;
        if (preview.length > 50) preview = preview.substring(0, 50) + '...';
        return preview;
    }
  }

  Future<void> _showForwardConfirmation(Map<String, dynamic> message) async {
    final preview = _getMessagePreview(message);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة توجيه الرسالة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إلى: ${currentGroup!.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            const Text(
              'المحتوى:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(preview),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _performForward(message);
    }
  }

  Future<void> _performForward(Map<String, dynamic> originalMessage) async {
    if (currentGroup == null) {
      _showCriticalError('خطأ: المجموعة غير جاهزة');
      return;
    }
    final String chatType = 'group';
    final String msgContent = originalMessage['message'] ?? '';
    String msgType = originalMessage['type'] ?? 'text';

    if (msgType == 'text') {
      if (_isImageMessage(msgContent))
        msgType = 'image';
      else if (_isVideoMessage(msgContent))
        msgType = 'video';
      else if (_isVoiceMessage(msgContent))
        msgType = 'voice';
      else if (msgContent.startsWith('LOCATION:')) msgType = 'location';
    }

    final tempId = 'temp_forward_${DateTime.now().millisecondsSinceEpoch}';
    final Map<String, dynamic> tempMessage = {
      "chat_id": currentGroup!.id,
      "sender_id": widget.currentUserId,
      "message": msgContent,
      "type": msgType,
      "chat_type": chatType,
      "created_at": DateTime.now().toIso8601String(),
      "id": tempId,
      "forwarded": true,
    };
    if (msgType == 'voice') {
      tempMessage['duration'] = originalMessage['duration'] ?? 5;
    }

    setState(() {
      _messages.insert(0, tempMessage);
      _messagesNotifier.value = _messages;
    });
    _autoScrollToLatest();

    try {
      final response = await http.post(
        Uri.parse("${widget.baseUrl}/messages/forward"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "chat_id": currentGroup!.id,
          "sender_id": widget.currentUserId,
          "message": msgContent,
          "type": msgType,
          "chat_type": chatType,
          "duration":
              msgType == 'voice' ? (originalMessage['duration'] ?? 5) : null,
        }),
      );
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['success'] == true) {
          final realMessage = resData['message'] as Map<String, dynamic>?;
          if (realMessage != null && realMessage['id'] != null) {
            realMessage['forwarded'] = true;
            final realId = realMessage['id'].toString();
            _saveForwardedId(realId);
            setState(() {
              final index = _messages.indexWhere((msg) => msg['id'] == tempId);
              if (index != -1) {
                _messages[index] = realMessage;
                _messagesNotifier.value = _messages;
              }
            });
            _showCriticalError('✅ تم إعادة التوجيه بنجاح');
          } else {
            setState(() {
              _messages.removeWhere((msg) => msg['id'] == tempId);
              _messagesNotifier.value = _messages;
            });
            await _loadMessages();
            _showCriticalError('✅ تم إعادة التوجيه بنجاح');
          }
        } else {
          throw Exception(resData['error'] ?? 'فشل الإرسال');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _messages.removeWhere((msg) => msg['id'] == tempId);
        _messagesNotifier.value = _messages;
      });
      _showCriticalError('❌ فشل إعادة التوجيه: ${e.toString()}');
    }
  }

  void _initializeSocket() {
    socket = IO.io(
      widget.baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(1000)
          .build(),
    );
    socket.connect();
    socket.onConnect((_) {
      print("✅ Socket connected: ${socket.id}");
      socket.emit("signin", widget.currentUserId);
      if (!isCreationMode && currentGroup != null) {
        socket.emit("join_chat", currentGroup!.id);
      }
    });
    socket.onConnectError((error) {
      print("❌ Socket connection error: $error");
    });
    socket.onReconnect((attempt) {
      print("🔄 Socket reconnecting, attempt: $attempt");
      if (!isCreationMode && currentGroup != null) {
        socket.emit("join_chat", currentGroup!.id);
      }
    });
    socket.onDisconnect((_) {
      print("⚠️ Socket disconnected");
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Future<void> _loadMessages() async {
    if (_hasLoadedMessages) return;
    if (currentGroup == null) {
      setState(() => isLoadingMessages = false);
      return;
    }
    try {
      final response = await http.get(
        Uri.parse(
          "${widget.baseUrl}/messages/${currentGroup!.id}?user_id=${widget.currentUserId}",
        ),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> loadedMessages = [];
        for (var msg in data.reversed) {
          Map<String, dynamic> message = Map<String, dynamic>.from(msg);
          final msgId = message['id'].toString();
          if (_forwardedMessageIds.contains(msgId)) {
            message['forwarded'] = true;
          } else if (message['original_sender'] != null) {
            message['forwarded'] = true;
            _saveForwardedId(msgId);
          } else {
            message['forwarded'] = false;
          }
          final replied = message['replied_message'];
          if (replied != null && replied is Map<String, dynamic>) {
            final repliedMsg = replied['message'] ?? '';
            final repliedSender = replied['sender_id'] ?? '';
            message['reply_to'] = {
              'message_id': message['reply_to_message_id'] ?? '',
              'message_text': repliedMsg,
              'sender_name': repliedSender == widget.currentUserId
                  ? 'أنت'
                  : (replied['sender_name'] ?? 'مستخدم'),
              'message_type': _getTypeFromMessage(repliedMsg),
              'duration': replied['duration'] ?? 0,
            };
          } else {
            message.remove('reply_to');
          }
          loadedMessages.add(message);
        }
        _messages = loadedMessages;
        _messagesNotifier.value = _messages;
        setState(() {
          isLoadingMessages = false;
          _hasLoadedMessages = true;
          _isChatReady = true;
        });
      } else {
        setState(() => isLoadingMessages = false);
      }
    } catch (e) {
      print("❌ خطأ في تحميل الرسائل: $e");
      setState(() => isLoadingMessages = false);
    }
  }

  void _listenToGroupMessages() {
    socket.on("message", (data) {
      if (data['chat_id'] != null && currentGroup != null) {
        if (data['chat_id'].toString() == currentGroup!.id) {
          setState(() {
            final exists = _messages.any((msg) => msg['id'] == data['id']);
            if (!exists) {
              final replied = data['replied_message'];
              if (replied != null && replied is Map<String, dynamic>) {
                final repliedMsg = replied['message'] ?? '';
                final repliedSender = replied['sender_id'] ?? '';
                data['reply_to'] = {
                  'message_id': data['reply_to_message_id'] ?? '',
                  'message_text': repliedMsg,
                  'sender_name': repliedSender == widget.currentUserId
                      ? 'أنت'
                      : (replied['sender_name'] ?? 'مستخدم'),
                  'message_type': _getTypeFromMessage(repliedMsg),
                  'duration': replied['duration'] ?? 0,
                };
              } else {
                data.remove('reply_to');
              }
              _messages.insert(0, data);
              _messagesNotifier.value = _messages;
              _autoScrollToLatest();
            }
          });
        }
      }
    });
  }

  // ==================== إرسال الرسالة ====================
  void _sendGroupMessage() {
    print(
      "🟢 _sendGroupMessage called, isChatReady=$_isChatReady, groupId=${currentGroup?.id}",
    );
    if (!_isChatReady || currentGroup == null) {
      _showCriticalError("المجموعة ليست جاهزة بعد، انتظر قليلاً");
      return;
    }
    if (_isChatLocked && !isAdmin) {
      _showCriticalError("الدردشة مقفلة، فقط المشرفون يمكنهم الإرسال");
      return;
    }
    final msgText = _messageController.text.trim();
    if (msgText.isEmpty) return;

    final replyToId = _replyingToMessage?['id']?.toString();

    final replyPreview = _replyingToMessage != null
        ? {
            'message_id': replyToId,
            'message_text': _replyingToMessage!['message'] ?? '',
            'sender_name':
                _replyingToMessage!['sender_id'] == widget.currentUserId
                    ? 'أنت'
                    : 'مستخدم',
            'message_type': _getTypeFromMessage(
              _replyingToMessage!['message'] ?? '',
            ),
            'duration': _replyingToMessage!['duration'],
          }
        : null;

    final tempMsg = {
      "chat_id": currentGroup!.id,
      "sender_id": widget.currentUserId,
      "message": msgText,
      "chat_type": "group",
      "created_at": DateTime.now().toIso8601String(),
      "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
      "reply_to": replyPreview,
    };

    setState(() {
      _messages.insert(0, tempMsg);
      _messagesNotifier.value = _messages;
      _messageController.clear();
      _cancelReply();
    });
    _autoScrollToLatest();

    socket.emit("message", {
      "chat_id": currentGroup!.id,
      "sender_id": widget.currentUserId,
      "message": msgText,
      "chat_type": "group",
      "reply_to_message_id": replyToId,
    });
  }

  void _autoScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _messages.isNotEmpty) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ==================== الردود ====================
  void _startReplyBySwipe(Map<String, dynamic> message) {
    setState(() {
      _replyingToMessage = message;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  Widget _buildReplyCard(Map<String, dynamic> replyTo, bool isMe) {
    final Map<String, dynamic> tempMessage = {
      'message': replyTo['message_text'] ?? '',
      'type': replyTo['message_type'] ?? '',
      'duration': replyTo['duration'] ?? 0,
    };
    final String previewText = _getMessagePreview(tempMessage);
    final String replySender = replyTo['sender_name'] ?? 'مستخدم';
    final bool isVoice =
        replyTo['message_type'] == 'voice' && (replyTo['duration'] ?? 0) > 0;
    final String durationText = isVoice
        ? ' (${_formatDuration(Duration(seconds: replyTo['duration']))})'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 2.5,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.blue[700],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                replySender,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
              const SizedBox(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.55,
                ),
                child: Text(
                  previewText + durationText,
                  style: TextStyle(fontSize: 11.5, color: Colors.blue[900]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar() {
    if (!_isReplying) return const SizedBox.shrink();
    final originalMsg = _replyingToMessage!;
    final preview = _getMessagePreview(originalMsg);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "الرد على: ${originalMsg['sender_id'] == widget.currentUserId ? 'نفسك' : 'مستخدم'}",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  // ==================== عرض محتوى الرسالة ====================
  Widget _buildMessageContent(
    Map<String, dynamic> msg,
    bool isMe,
    String msgId,
  ) {
    final String msgContent = msg['message'] ?? "";
    final String msgType = msg['type'] ?? "";
    final int duration = msg['duration'] ?? 0;
    final String time = _formatTimeForBubble(msg['created_at']);
    final bool isForwarded = msg['forwarded'] == true;
    final replyTo = msg['reply_to'];

    final bool isImg = _isImageMessage(msgContent);
    final bool isVideo = _isVideoMessage(msgContent);
    final bool isDoc = _isDocumentMessage(msgContent);
    final bool isLoc = msgContent.startsWith("LOCATION:");
    final bool isVoice = msgType == 'voice' || _isVoiceMessage(msgContent);

    if (replyTo == null || replyTo is! Map) {
      if (isLoc)
        return _buildLocationMessage(msgContent, isMe, msgId, isForwarded);
      if (isImg) return _buildImageWidget(msg, isMe, isForwarded);
      if (isVideo)
        return _buildVideoWidget(msgContent, isMe, msgId, isForwarded);
      if (isDoc) return _buildDocumentWidget(msgContent, isMe, isForwarded);
      if (isVoice)
        return _buildVoiceMessageWidget(
          msgContent,
          isMe,
          duration,
          msgId,
          isForwarded,
        );
      return _buildTextBubble(msgContent, isMe, time, isForwarded: isForwarded);
    }

    final Map<String, dynamic> safeReplyTo = Map<String, dynamic>.from(replyTo);

    Widget innerContent;
    if (isLoc) {
      innerContent = _buildLocationMessage(
        msgContent,
        isMe,
        msgId,
        isForwarded,
      );
    } else if (isImg) {
      innerContent = _buildImageWidget(msg, isMe, isForwarded);
    } else if (isVideo) {
      innerContent = _buildVideoWidget(msgContent, isMe, msgId, isForwarded);
    } else if (isDoc) {
      innerContent = _buildDocumentWidget(msgContent, isMe, isForwarded);
    } else if (isVoice) {
      innerContent = _buildVoiceMessageWidget(
        msgContent,
        isMe,
        duration,
        msgId,
        isForwarded,
      );
    } else {
      innerContent = Padding(
        padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
        child: Text(
          msgContent,
          style: const TextStyle(fontSize: 16, color: Colors.black87),
        ),
      );
    }

    double? exactWidth;
    if (isVoice) {
      exactWidth = 240;
    } else if (isImg || isVideo) {
      exactWidth = 250;
    } else if (isDoc) {
      exactWidth = 260;
    }

    Widget bubbleWidget = Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFD9E5FC) : const Color(0xFFE8EDF5),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isMe ? 14 : 2),
          bottomRight: Radius.circular(isMe ? 2 : 14),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth:
                    exactWidth ?? MediaQuery.of(context).size.width * 0.65,
              ),
              child: _buildReplyCard(safeReplyTo, isMe),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: exactWidth != null
                ? SizedBox(width: exactWidth, child: innerContent)
                : innerContent,
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.done_all, size: 14, color: Colors.blue),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: exactWidth != null
          ? bubbleWidget
          : IntrinsicWidth(child: bubbleWidget),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, int index) {
    final bool isMe = msg['sender_id'].toString() == widget.currentUserId;
    final String msgId = msg['id'].toString();
    final bool isSelected = selectedMessageIds.contains(msgId);
    final bool showAvatar =
        !isMe && _shouldShowAvatar(index, msg['sender_id'].toString());

    double _dragOffset = 0.0;
    bool _isDragging = false;

    Widget messageContentWidget = Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe && showAvatar)
          Padding(
            padding: const EdgeInsets.only(bottom: 2, left: 8),
            child: FutureBuilder<String>(
              future: _getSenderName(msg['sender_id'].toString()),
              builder: (ctx, snapshot) => Text(
                snapshot.data ?? "...",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        _buildMessageContent(msg, isMe, msgId),
      ],
    );

    Widget selectionIconWidget = isSelectionMode
        ? Padding(
            padding: EdgeInsets.only(left: isMe ? 8 : 0, right: isMe ? 0 : 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                key: ValueKey(isSelected),
                color: Colors.blue,
                size: 22,
              ),
            ),
          )
        : const SizedBox.shrink();

    Widget avatarWidget = !isMe
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAvatar)
                FutureBuilder<String?>(
                  future: _getMemberAvatar(msg['sender_id'].toString()),
                  builder: (ctx, snapshot) {
                    final avatarUrl = snapshot.data;
                    return GestureDetector(
                      onTap: () => _showProfileImage(avatarUrl),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundImage:
                            avatarUrl != null && avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? const Icon(Icons.person, size: 20)
                            : null,
                      ),
                    );
                  },
                )
              else
                const SizedBox(width: 40),
              const SizedBox(width: 8),
            ],
          )
        : const SizedBox.shrink();

    Widget messageRow = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isMe
            ? [messageContentWidget, selectionIconWidget]
            : [selectionIconWidget, avatarWidget, messageContentWidget],
      ),
    );

    if (isSelectionMode) {
      return GestureDetector(
        onTap: () => _toggleMessageSelection(msgId),
        child: messageRow,
      );
    }

    return StatefulBuilder(
      builder: (context, setStateLocal) {
        return GestureDetector(
          onHorizontalDragStart: (details) {
            _isDragging = true;
            _dragOffset = 0.0;
            setStateLocal(() {});
          },
          onHorizontalDragUpdate: (details) {
            if (!_isDragging) return;
            double newOffset = _dragOffset + details.delta.dx;
            if (newOffset < 0) {
              _dragOffset = newOffset.clamp(-100.0, 0.0);
            } else {
              _dragOffset = 0.0;
            }
            setStateLocal(() {});
          },
          onHorizontalDragEnd: (details) {
            if (_isDragging) {
              if (_dragOffset < -40) {
                _startReplyBySwipe(msg);
              }
              _isDragging = false;
              _dragOffset = 0.0;
              setStateLocal(() {});
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_isDragging && _dragOffset < -10)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 70,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.reply,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(_dragOffset, 0),
                child: messageRow,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _getSenderName(String senderId) async {
    if (senderId == widget.currentUserId) return "أنت";
    try {
      final response = await http.get(
        Uri.parse("${widget.baseUrl}/users/$senderId"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['username'] ?? "مستخدم";
      }
    } catch (_) {}
    return "مستخدم";
  }

  Future<Map<String, String>> _getMemberDetails(String userId) async {
    if (userId == widget.currentUserId) return {'name': 'أنت', 'avatar': ''};
    try {
      final response = await http.get(
        Uri.parse("${widget.baseUrl}/users/$userId"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'name': data['username'] ?? 'مستخدم',
          'avatar': data['avatar_url'] ?? '',
        };
      }
    } catch (_) {}
    return {'name': 'مستخدم', 'avatar': ''};
  }

  Future<String?> _getMemberAvatar(String userId) async {
    if (userId == widget.currentUserId) return null;
    if (_memberAvatarCache.containsKey(userId)) {
      return await _memberAvatarCache[userId]!;
    }
    final future = _fetchAvatar(userId);
    _memberAvatarCache[userId] = future;
    return await future;
  }

  Future<String?> _fetchAvatar(String userId) async {
    try {
      final response = await http.get(
        Uri.parse("${widget.baseUrl}/users/$userId"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final avatarUrl = data['avatar_url'] as String?;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          return _getFullAvatarUrl(avatarUrl);
        }
      }
    } catch (_) {}
    return null;
  }

  void _showProfileImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black.withOpacity(0.9),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white, size: 50),
                    SizedBox(height: 10),
                    Text(
                      "فشل تحميل الصورة",
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimeForBubble(dynamic createdAt) {
    if (createdAt == null) return "";
    try {
      final dt = DateTime.parse(createdAt.toString()).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return "";
    }
  }

  bool _isImageMessage(String message) {
    final lower = message.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif');
  }

  bool _isVideoMessage(String message) {
    final lower = message.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv');
  }

  bool _isVoiceMessage(String message) {
    final lower = message.toLowerCase();
    return lower.contains('voice_') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac');
  }

  bool _isDocumentMessage(String message) {
    if (message.startsWith("LOCATION:")) return false;
    if (_isImageMessage(message)) return false;
    if (_isVideoMessage(message)) return false;
    if (_isVoiceMessage(message)) return false;
    return message.toLowerCase().contains('.');
  }

  String? _getFullAvatarUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return null;
    if (url.startsWith('http')) return url;
    String cleanUrl = url.startsWith('/') ? url.substring(1) : url;
    if (cleanUrl.startsWith('uploads_camera/'))
      cleanUrl = cleanUrl.substring('uploads_camera/'.length);
    if (cleanUrl.startsWith('uploads/'))
      cleanUrl = cleanUrl.substring('uploads/'.length);
    if (cleanUrl.startsWith('camera-'))
      return "${widget.baseUrl}/uploads_camera/$cleanUrl";
    else if (_isVoiceMessage(cleanUrl))
      return "${widget.baseUrl}/uploads/$cleanUrl";
    else if (cleanUrl.endsWith('.mp4') ||
        cleanUrl.endsWith('.mov') ||
        cleanUrl.endsWith('.avi'))
      return "${widget.baseUrl}/uploads_camera/$cleanUrl";
    else if (_isImageMessage(cleanUrl))
      return "${widget.baseUrl}/uploads/$cleanUrl";
    else
      return "${widget.baseUrl}/uploads/$cleanUrl";
  }

  void _showImageOnly(String? imageUrl) {
    if (imageUrl == null) return;
    showDialog(
      context: context,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black.withOpacity(0.9),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white, size: 50),
                    SizedBox(height: 10),
                    Text(
                      "فشل تحميل الصورة",
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCriticalError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.black87),
    );
  }

  // ==================== رفع الملفات والوسائط ====================
  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image != null) {
      Navigator.pop(context);
      final bytes = await image.readAsBytes();
      _showPreviewDialog(image, bytes);
    }
  }

  Future<void> _pickAndUploadDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      Navigator.pop(context);
      final file = result.files.first;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("${widget.baseUrl}/chat/upload"),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'chat_file',
          bytes,
          filename: file.name,
          contentType: MediaType('application', 'octet-stream'),
        ),
      );
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        String fileName = responseData['url'];
        var messageData = {
          "chat_id": currentGroup!.id,
          "sender_id": widget.currentUserId,
          "message": fileName,
          "chat_type": "group",
        };
        setState(() {
          _messages.insert(0, {
            ...messageData,
            "created_at": DateTime.now().toIso8601String(),
            "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
          });
          _messagesNotifier.value = _messages;
        });
        _autoScrollToLatest();
        socket.emit("message", messageData);
      } else
        _showCriticalError("خطأ في السيرفر: ${response.statusCode}");
    }
  }

  void _showPreviewDialog(XFile xFile, Uint8List bytes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: const Text(
              "معاينة الصورة",
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: Center(child: Image.memory(bytes)),
          floatingActionButton: FloatingActionButton(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.send, color: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _uploadAndSendImage(xFile, bytes);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _uploadAndSendImage(XFile xFile, Uint8List bytes) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("${widget.baseUrl}/chat/upload"),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'chat_file',
          bytes,
          filename: xFile.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        String fileName = responseData['url'];
        var messageData = {
          "chat_id": currentGroup!.id,
          "sender_id": widget.currentUserId,
          "message": fileName,
          "chat_type": "group",
        };
        socket.emit("message", messageData);
        setState(() {
          _messages.insert(0, {
            ...messageData,
            "created_at": DateTime.now().toIso8601String(),
            "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
          });
          _messagesNotifier.value = _messages;
        });
        _autoScrollToLatest();
      } else
        _showCriticalError("خطأ في السيرفر: ${response.statusCode}");
    } catch (_) {
      _showCriticalError("تعذر رفع الصورة.");
    }
  }

  void _showPreviewFromCamera(Uint8List bytes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: const Text(
              "معاينة الصورة",
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: Center(child: Image.memory(bytes)),
          floatingActionButton: FloatingActionButton(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.send, color: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _uploadAndSendImageFromCamera(bytes);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _uploadAndSendImageFromCamera(Uint8List bytes) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("${widget.baseUrl}/chat/upload"),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'chat_file',
          bytes,
          filename: "camera_image_${DateTime.now().millisecondsSinceEpoch}.jpg",
          contentType: MediaType('image', 'jpeg'),
        ),
      );
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        String fileName = responseData['url'];
        var messageData = {
          "chat_id": currentGroup!.id,
          "sender_id": widget.currentUserId,
          "message": fileName,
          "chat_type": "group",
        };
        socket.emit("message", messageData);
        setState(() {
          _messages.insert(0, {
            ...messageData,
            "created_at": DateTime.now().toIso8601String(),
            "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
          });
          _messagesNotifier.value = _messages;
        });
        _autoScrollToLatest();
      } else
        _showCriticalError("خطأ في السيرفر: ${response.statusCode}");
    } catch (_) {
      _showCriticalError("تعذر رفع الصورة الملتقطة.");
    }
  }

  Future<void> _openMapPicker() async {
    Navigator.pop(context);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocationPickerPage()),
    );
    if (result != null) {
      double lat = result['lat'], lng = result['lng'];
      String locationString = "LOCATION:$lat,$lng";
      var messageData = {
        "chat_id": currentGroup!.id,
        "sender_id": widget.currentUserId,
        "message": locationString,
        "chat_type": "group",
      };
      socket.emit("message", messageData);
      setState(() {
        _messages.insert(0, {
          ...messageData,
          "created_at": DateTime.now().toIso8601String(),
          "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
        });
        _messagesNotifier.value = _messages;
      });
      _autoScrollToLatest();
    }
  }

  Widget _iconCreation(
    IconData icons,
    Color color,
    String text,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: color,
            child: Icon(icons, size: 29, color: Colors.white),
          ),
          const SizedBox(height: 5),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _showAttachSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: 220,
        width: MediaQuery.of(context).size.width,
        child: Card(
          margin: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, // ✅ توسيط الأيقونات
              children: [
                // المستندات
                _iconCreation(
                  Icons.insert_drive_file,
                  Colors.indigo,
                  "المستندات",
                  _pickAndUploadDocument,
                ),
                const SizedBox(width: 40), // ✅ مسافة بين الأيقونات
                // المعرض
                _iconCreation(
                  Icons.insert_photo,
                  Colors.purple,
                  "المعرض",
                  _pickImageFromGallery,
                ),
                const SizedBox(width: 40),
                // الموقع
                _iconCreation(
                  Icons.location_on,
                  const Color.fromARGB(255, 233, 152, 30),
                  "الموقع",
                  _openMapPicker,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== التحديد المتعدد والإجراءات ====================
  void _exitSelectionMode() {
    setState(() {
      isSelectionMode = false;
      selectedMessageIds.clear();
      _selectedAction = '';
    });
  }

  void _toggleMessageSelection(String msgId) {
    setState(() {
      if (selectedMessageIds.contains(msgId)) {
        selectedMessageIds.remove(msgId);
      } else {
        selectedMessageIds.add(msgId);
      }
      if (selectedMessageIds.isEmpty) {
        isSelectionMode = false;
        _selectedAction = '';
      }
    });
  }

  void _copySingleMessage(Map<String, dynamic> msg) {
    final String msgContent = msg['message'] ?? '';
    Clipboard.setData(ClipboardData(text: msgContent));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("تم نسخ النص")));
  }

  void _activateSelectionMode(
    Map<String, dynamic> msg, {
    required String action,
  }) {
    final String msgId = msg['id'].toString();
    setState(() {
      isSelectionMode = true;
      _selectedAction = action;
      selectedMessageIds.clear();
      selectedMessageIds.add(msgId);
    });
  }

  void _executeBulkAction() {
    if (selectedMessageIds.isEmpty) return;
    final selectedMessages = _messages
        .where((msg) => selectedMessageIds.contains(msg['id'].toString()))
        .toList();
    switch (_selectedAction) {
      case 'delete_for_me':
        _handleBulkDelete(forEveryone: false);
        break;
      case 'delete_for_everyone':
        _handleBulkDelete(forEveryone: true);
        break;
      case 'share':
        _handleBulkShare();
        break;
      case 'forward':
        _forwardMultipleMessages(selectedMessages);
        break;
      case 'select':
        break;
    }
    if (_selectedAction != 'select') {
      _exitSelectionMode();
    }
  }

  void _showOptionsPopupMenu(
    BuildContext context,
    Map<String, dynamic> msg,
    Offset tapPosition,
  ) {
    final bool isMe = msg['sender_id'] == widget.currentUserId;
    final String msgContent = msg['message'] ?? '';
    final bool isTextMessage = !_isImageMessage(msgContent) &&
        !_isVideoMessage(msgContent) &&
        !_isVoiceMessage(msgContent) &&
        !msgContent.startsWith("LOCATION:");

    final List<PopupMenuEntry<String>> items = [];

    items.add(
      const PopupMenuItem<String>(
        value: 'forward',
        child: Row(
          children: [
            Icon(Icons.forward, color: Colors.orange, size: 20),
            SizedBox(width: 12),
            Text("إعادة توجيه"),
          ],
        ),
      ),
    );

    if (isTextMessage) {
      items.add(
        const PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, color: Colors.grey),
              SizedBox(width: 12),
              Text("نسخ"),
            ],
          ),
        ),
      );
    }
    items.add(
      const PopupMenuItem<String>(
        value: 'share',
        child: Row(
          children: [
            Icon(Icons.share, color: Colors.green),
            SizedBox(width: 12),
            Text("مشاركة"),
          ],
        ),
      ),
    );
    items.add(
      const PopupMenuItem<String>(
        value: 'delete_for_me',
        child: Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 12),
            Text("حذف لدي", style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
    if (isMe) {
      items.add(
        const PopupMenuItem<String>(
          value: 'delete_for_everyone',
          child: Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 12),
              Text("حذف للجميع", style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      );
    }

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromLTRB(
      tapPosition.dx,
      tapPosition.dy,
      overlay.size.width - tapPosition.dx,
      overlay.size.height - tapPosition.dy,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: items,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'forward':
          _executeForwardMessage(msg);
          break;
        case 'copy':
          _copySingleMessage(msg);
          break;
        case 'share':
          _activateSelectionMode(msg, action: 'share');
          break;
        case 'delete_for_me':
          _activateSelectionMode(msg, action: 'delete_for_me');
          break;
        case 'delete_for_everyone':
          _activateSelectionMode(msg, action: 'delete_for_everyone');
          break;
      }
    });
  }

  Future<void> _executeForwardMessage(
    Map<String, dynamic> originalMessage,
  ) async {
    final navigator = Navigator.of(context);
    final currentChatId = currentGroup?.id;
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (context) => ChatPageForForward(
          currentUserId: widget.currentUserId,
          socket: socket,
          showAppBar: true,
          initialSearchQuery: '',
          messageToForward: originalMessage,
          onForwardComplete: (success, targetChatName, targetChatId) {
            if (success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("✅ تمت إعادة التوجيه إلى $targetChatName"),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
              if (targetChatId == currentChatId) {
                setState(() {
                  _messages.insert(0, {
                    ...originalMessage,
                    "created_at": DateTime.now().toIso8601String(),
                    "id": "forward_${DateTime.now().millisecondsSinceEpoch}",
                    "forwarded": true,
                  });
                  _messagesNotifier.value = _messages;
                });
                _autoScrollToLatest();
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _forwardMultipleMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    for (var msg in messages) {
      await _executeForwardMessage(msg);
    }
  }

  String _getTypeFromMessage(String message) {
    if (_isImageMessage(message)) return 'image';
    if (_isVideoMessage(message)) return 'video';
    if (_isVoiceMessage(message)) return 'voice';
    if (_isDocumentMessage(message)) return 'document';
    if (message.startsWith("LOCATION:")) return 'location';
    return 'text';
  }

  Future<void> _shareMessage(Map<String, dynamic> message) async {
    await _shareMultipleMessages([message]);
  }

  Future<void> _shareMultipleMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    final texts = messages.map((msg) {
      final content = msg['message'] ?? '';
      if (content.startsWith("LOCATION:")) {
        final coords = content.replaceFirst("LOCATION:", "").split(",");
        return "https://www.google.com/maps/search/?api=1&query=${coords[0]},${coords[1]}";
      }
      return content;
    }).join("\n\n");
    await Share.share(texts);
  }

  void _handleBulkDelete({bool forEveryone = false}) {
    for (var id in selectedMessageIds) {
      if (forEveryone) {
        final msg = _messages.firstWhere((m) => m['id'].toString() == id);
        if (msg['sender_id'] == widget.currentUserId) {
          socket.emit("delete_message", {
            "message_id": id,
            "chat_id": currentGroup!.id,
          });
        }
      } else {
        socket.emit("delete_for_me", {
          "message_id": id,
          "user_id": widget.currentUserId,
        });
      }
      _messages.removeWhere((m) => m['id'].toString() == id);
    }
    _messagesNotifier.value = _messages;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          forEveryone ? "تم حذف الرسائل للجميع" : "تم حذف الرسائل لديك",
        ),
      ),
    );
  }

  void _handleBulkCopy() {
    final text = _messages
        .where((m) => selectedMessageIds.contains(m['id'].toString()))
        .map((m) => m['message'] ?? '')
        .toList()
        .reversed
        .join("\n");
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("تم نسخ الرسائل المختارة")));
  }

  void _handleBulkShare() {
    final selectedMessages = _messages
        .where((msg) => selectedMessageIds.contains(msg['id'].toString()))
        .toList();
    _shareMultipleMessages(selectedMessages);
  }

  bool _areAllSelectedMessagesMine() {
    if (selectedMessageIds.isEmpty) return false;
    return _messages
        .where((m) => selectedMessageIds.contains(m['id'].toString()))
        .every((m) => m['sender_id'] == widget.currentUserId);
  }

  // ==================== دوال عرض الرسائل ====================
  Color _getBubbleColor(bool isMe, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return isMe ? const Color(0xFF1E88E5) : const Color(0xFF2A2A2A);
    } else {
      return isMe
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.white;
    }
  }

  BorderRadius _getBubbleBorderRadius(bool isMe) {
    if (isMe) {
      return const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(4),
      );
    } else {
      return const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(4),
        bottomRight: Radius.circular(18),
      );
    }
  }

  bool _shouldShowAvatar(int currentIndex, String currentSenderId) {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= _messages.length) return true;
    final nextMsg = _messages[nextIndex];
    final nextSenderId = nextMsg['sender_id'].toString();
    return currentSenderId != nextSenderId;
  }

  Widget _buildLocationMessage(
    String msg,
    bool isMe,
    String msgId,
    bool isForwarded,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeColor = isDark ? Colors.white70 : Colors.grey.shade600;
    final coords = msg.replaceFirst("LOCATION:", "").split(",");
    return InkWell(
      onTap: () async {
        if (isSelectionMode) {
          _toggleMessageSelection(msgId);
        } else {
          await launchUrl(
            Uri.parse(
              "https://www.google.com/maps/search/?api=1&query=${coords[0]},${coords[1]}",
            ),
            mode: LaunchMode.externalApplication,
          );
        }
      },
      onLongPress: () {
        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
        final Offset position =
            renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
        _showOptionsPopupMenu(
            context,
            {
              'id': msgId,
              'sender_id': '',
              'message': msg,
            },
            position);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getBubbleColor(isMe, context),
          borderRadius: _getBubbleBorderRadius(isMe),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isForwarded)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.repeat, size: 12, color: timeColor),
                    const SizedBox(width: 4),
                    Text(
                      "↺ تمت إعادة التوجيه",
                      style: TextStyle(fontSize: 10, color: timeColor),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on, color: Colors.red, size: 18),
                const SizedBox(width: 6),
                Text(
                  "موقع",
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(dynamic msgData, bool isMe, bool isForwarded) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String imageUrl = "";
    String? caption;
    if (msgData is Map) {
      imageUrl = msgData['message']?.toString() ?? "";
      caption = msgData['caption']?.toString();
    } else {
      imageUrl = msgData.toString();
    }
    final rawPath = _getFullAvatarUrl(imageUrl) ?? "";
    final timeColor = isDark ? Colors.white70 : Colors.grey.shade600;

    return GestureDetector(
      onTap: () => _showImageOnly(rawPath),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _getBubbleColor(isMe, context),
          borderRadius: _getBubbleBorderRadius(isMe),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isForwarded)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, right: 4, left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.repeat, size: 12, color: timeColor),
                    const SizedBox(width: 4),
                    Text(
                      "↺ تمت إعادة التوجيه",
                      style: TextStyle(fontSize: 10, color: timeColor),
                    ),
                  ],
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                rawPath,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                cacheWidth: 200,
                cacheHeight: 200,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  width: 200,
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.broken_image,
                        color: isDark ? Colors.white60 : Colors.grey,
                      ),
                      const Text("فشل تحميل الصورة"),
                    ],
                  ),
                ),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            if (caption != null && caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 5, left: 5),
                child: Text(
                  caption,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoWidget(
    String videoUrl,
    bool isMe,
    String messageId,
    bool isForwarded,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fullUrl = _getFullAvatarUrl(videoUrl);
    final timeColor = isDark ? Colors.white70 : Colors.grey.shade600;
    if (fullUrl == null || fullUrl.isEmpty) {
      return Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _getBubbleColor(isMe, context),
          borderRadius: _getBubbleBorderRadius(isMe),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, size: 50, color: Colors.grey),
            Text("فيديو غير متوفر"),
          ],
        ),
      );
    }
    return Container(
      width: 250,
      constraints: const BoxConstraints(maxWidth: 280),
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isForwarded)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, right: 8, left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.repeat, size: 12, color: timeColor),
                    const SizedBox(width: 4),
                    Text(
                      "↺ تمت إعادة التوجيه",
                      style: TextStyle(fontSize: 10, color: timeColor),
                    ),
                  ],
                ),
              ),
            VideoPlayerWidget(
              url: fullUrl,
              isMe: isMe,
              videoId: messageId,
              onPlayStateChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentWidget(String fileName, bool isMe, bool isForwarded) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeColor = isDark ? Colors.white70 : Colors.grey.shade600;
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      decoration: BoxDecoration(
        color: _getBubbleColor(isMe, context),
        borderRadius: _getBubbleBorderRadius(isMe),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isForwarded)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 8, left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.repeat, size: 12, color: timeColor),
                  const SizedBox(width: 4),
                  Text(
                    "↺ تمت إعادة التوجيه",
                    style: TextStyle(fontSize: 10, color: timeColor),
                  ),
                ],
              ),
            ),
          _buildDocumentItem(fileName),
        ],
      ),
    );
  }

  Widget _buildVoiceMessageWidget(
    String fileName,
    bool isMe,
    int duration,
    String msgId,
    bool isForwarded,
  ) {
    final fullUrl = _getFullAvatarUrl(fileName);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeColor = isDark ? Colors.white70 : Colors.grey.shade600;
    if (fullUrl == null || fullUrl.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _getBubbleColor(isMe, context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text('ملف صوتي غير متوفر'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isForwarded)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 8, left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.repeat, size: 12, color: timeColor),
                const SizedBox(width: 4),
                Text(
                  "↺ تمت إعادة التوجيه",
                  style: TextStyle(fontSize: 10, color: timeColor),
                ),
              ],
            ),
          ),
        UniversalAudioPlayer(
          audioUrl: fullUrl,
          isMe: isMe,
          primaryColor: Colors.blue,
          onPlayStateChanged: () {},
          onError: () => _showCriticalError('حدث خطأ في تشغيل الصوت'),
        ),
      ],
    );
  }

  Widget _buildTextBubble(
    String text,
    bool isMe,
    String time, {
    bool isForwarded = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = _getBubbleColor(isMe, context);
    final textColor = isDark
        ? Colors.white
        : (isMe
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface);
    final timeColor = isDark ? Colors.white70 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: _getBubbleBorderRadius(isMe),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isForwarded)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.repeat, size: 12, color: timeColor),
                  const SizedBox(width: 4),
                  Text(
                    "↺ تمت إعادة التوجيه",
                    style: TextStyle(fontSize: 10, color: timeColor),
                  ),
                ],
              ),
            ),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: timeColor,
                ),
              ),
              const SizedBox(width: 4),
              if (isMe)
                Icon(
                  Icons.done_all,
                  size: 14,
                  color: isDark ? Colors.white70 : Colors.blue.shade400,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentItem(String fileName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    IconData fileIcon = Icons.insert_drive_file;
    Color iconColor =
        isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);
    if (fileName.toLowerCase().endsWith('.pdf')) {
      fileIcon = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (fileName.toLowerCase().contains('.xls')) {
      fileIcon = Icons.table_chart;
      iconColor = Colors.green;
    } else if (fileName.toLowerCase().contains('.doc')) {
      fileIcon = Icons.description;
      iconColor = Colors.blue;
    }
    return InkWell(
      onTap: () async {
        final urlString = _getFullAvatarUrl(fileName);
        if (urlString == null) return;
        try {
          if (kIsWeb) {
            await launchUrl(
              Uri.parse(urlString),
              mode: LaunchMode.externalApplication,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("جاري معالجة الملف..."),
                duration: Duration(seconds: 1),
              ),
            );
            final tempDir = await getTemporaryDirectory();
            final savePath = "${tempDir.path}/${fileName.split('/').last}";
            File file = File(savePath);
            if (!await file.exists()) await Dio().download(urlString, savePath);
            await OpenFile.open(savePath);
          }
        } catch (_) {
          _showCriticalError("خطأ في فتح الملف");
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fileIcon, color: iconColor, size: 30),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                fileName.split('/').last,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== شرائط التطبيق ====================
  AppBar _buildSelectionAppBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black;
    IconData actionIcon;
    String actionText;
    Color actionColor;
    switch (_selectedAction) {
      case 'delete_for_me':
      case 'delete_for_everyone':
        actionIcon = Icons.delete;
        actionText = "حذف";
        actionColor = Colors.red;
        break;
      case 'share':
        actionIcon = Icons.share;
        actionText = "مشاركة";
        actionColor = Colors.green;
        break;
      case 'forward':
        actionIcon = Icons.forward;
        actionText = "إعادة توجيه";
        actionColor = Colors.orange;
        break;
      default:
        actionIcon = Icons.check_circle;
        actionText = "تحديد";
        actionColor = Colors.blue;
    }
    return AppBar(
      backgroundColor: isDark ? Colors.black : Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close, color: iconColor),
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        "اختر ${selectedMessageIds.length} رسالة",
        style: TextStyle(color: iconColor),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: ElevatedButton.icon(
            onPressed: _executeBulkAction,
            icon: Icon(actionIcon, color: Colors.white, size: 20),
            label: Text(
              actionText,
              style: const TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: actionColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ],
    );
  }

  AppBar _buildNormalAppBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white : Colors.black;
    return AppBar(
      backgroundColor: isDark ? Colors.black : Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: iconColor),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          GestureDetector(
            onTap: () => _showImageOnly(_getFullAvatarUrl(currentGroup!.icon)),
            child: Hero(
              tag: "avatar_hero",
              child: CircleAvatar(
                radius: 19,
                backgroundImage: currentGroup!.icon.isNotEmpty
                    ? NetworkImage(_getFullAvatarUrl(currentGroup!.icon)!)
                    : null,
                child: currentGroup!.icon.isEmpty
                    ? Icon(Icons.group, color: iconColor)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentGroup!.name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
              Text(
                "${currentGroup!.participants.length} عضواً",
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.info_outline, color: iconColor),
          onPressed: _showGroupMembersPage,
        ),
      ],
    );
  }

  void _showGroupMembersPage() {
    if (currentGroup == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupMembersPage(
          currentGroup: currentGroup!,
          currentUserId: widget.currentUserId,
          baseUrl: widget.baseUrl,
          socket: socket,
          onGroupDeleted: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
          onLockChanged: (v) => setState(() => _isChatLocked = v),
          onClearChatLocally: () {
            setState(() {
              _messages.clear();
              _messagesNotifier.value = _messages;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("تم مسح الدردشة من جهازك")),
            );
          },
        ),
      ),
    );
  }

  // ==================== واجهة إنشاء المجموعة ====================
  Widget _buildCreationUI() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "إنشاء مجموعة جديدة",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: const Text(
              "إنشاء",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ================== بطاقة الصورة واسم المجموعة ==================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickGroupImage,
                        child: Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                                image: _groupImageBytes != null
                                    ? DecorationImage(
                                        image: MemoryImage(_groupImageBytes!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _groupImageBytes == null
                                  ? Icon(
                                      Icons.camera_alt,
                                      size: 40,
                                      color: colorScheme.onSurfaceVariant,
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _groupNameController,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "اسم المجموعة *",
                        prefixIcon: Icon(
                          Icons.group,
                          color: colorScheme.primary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color:
                                isDark ? Colors.grey[600]! : Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? "يرجى إدخال اسم المجموعة"
                              : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ================== بطاقة الأعضاء ==================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "الأعضاء",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _selectMembers,
                          icon: Icon(
                            Icons.person_add,
                            color: colorScheme.primary,
                          ),
                          label: Text(
                            "إضافة (${selectedMembers.length})",
                            style: TextStyle(color: colorScheme.primary),
                          ),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (selectedMembers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 48,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "لم يتم اختيار أي أعضاء بعد",
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "اضغط على زر 'إضافة' لاختيار الأعضاء",
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: selectedMembers.length,
                        itemBuilder: (ctx, i) {
                          final member = selectedMembers[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color:
                                  isDark ? Colors.grey[800] : Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: member.icon.isNotEmpty
                                    ? NetworkImage(
                                        _getFullAvatarUrl(member.icon)!,
                                      )
                                    : null,
                                child: member.icon.isEmpty
                                    ? Icon(
                                        Icons.person,
                                        color: colorScheme.onSurfaceVariant,
                                      )
                                    : null,
                              ),
                              title: Text(
                                member.name,
                                style: TextStyle(color: colorScheme.onSurface),
                              ),
                              subtitle: Text(
                                member.status,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    setState(() => selectedMembers.removeAt(i)),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ================== بطاقة معلومات ==================
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "سيتم إضافتك تلقائياً كعضو في المجموعة. المجموع الكلي: ${selectedMembers.length + 1} عضو.",
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _selectMembers() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectMembers(
          currentUserId: widget.currentUserId,
          multiSelect: true,
        ),
      ),
    );
    if (result != null && result is List<String>) {
      setState(() {
        selectedMembers = result
            .map(
              (uid) => ChatModel(
                id: uid,
                name: "جارٍ التحميل...",
                icon: "",
                status: "",
                isOnline: false,
                lastSeen: "",
                permissions: [],
                isGroup: false,
                participants: [],
                createdBy: "",
                time: "",
                currentMessage: "",
              ),
            )
            .toList();
      });

      List<ChatModel> loadedMembers = [];
      for (String uid in result) {
        final userData = await _fetchUserDetails(uid);
        loadedMembers.add(userData);
      }
      setState(() {
        selectedMembers = loadedMembers;
      });
    } else if (result != null && result is List<ChatModel>) {
      setState(() => selectedMembers = result);
    } else {
      _showCriticalError("لم يتم اختيار أي أعضاء");
    }
  }

  Future<ChatModel> _fetchUserDetails(String userId) async {
    try {
      final response = await http.get(
        Uri.parse("${widget.baseUrl}/users/$userId"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ChatModel(
          id: data['id']?.toString() ?? userId,
          name: data['username']?.toString() ?? 'مستخدم',
          icon: data['avatar_url']?.toString() ?? '',
          status: data['job']?.toString() ?? 'لا توجد وظيفة',
          isOnline: data['is_online'] ?? false,
          lastSeen: data['last_seen']?.toString() ?? '',
          permissions: List<String>.from(data['permissions'] ?? []),
          isGroup: false,
          participants: [],
          createdBy: '',
          time: '',
          currentMessage: '',
        );
      }
    } catch (e) {
      print("خطأ في جلب بيانات المستخدم $userId: $e");
    }
    return ChatModel(
      id: userId,
      name: 'مستخدم',
      icon: '',
      status: '',
      isOnline: false,
      lastSeen: '',
      permissions: [],
      isGroup: false,
      participants: [],
      createdBy: '',
      time: '',
      currentMessage: '',
    );
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) {
      _showCriticalError("يرجى إدخال اسم للمجموعة");
      return;
    }
    if (selectedMembers.length < 2) {
      _showCriticalError("يجب اختيار عضوين على الأقل (بالإضافة إليك)");
      return;
    }
    setState(() => _isCreating = true);
    String? uploadedImageUrl;
    if (_groupImageBytes != null) {
      try {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse("${widget.baseUrl}/chat/upload"),
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'chat_file',
            _groupImageBytes!,
            filename: 'group_${DateTime.now().millisecondsSinceEpoch}.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);
        if (response.statusCode == 200 || response.statusCode == 201) {
          uploadedImageUrl = jsonDecode(response.body)['url'];
        }
      } catch (_) {}
    }
    final memberIds = [
      ...selectedMembers.map((m) => m.id),
      widget.currentUserId,
    ];
    try {
      final response = await http.post(
        Uri.parse("${widget.baseUrl}/groups/create"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": _groupNameController.text.trim(),
          "members": memberIds,
          "created_by": widget.currentUserId,
          "icon": uploadedImageUrl ?? "",
          "locked": false,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final groupData = jsonDecode(response.body);
        final newGroup = ChatModel(
          id: groupData['id'].toString(),
          name: groupData['name'],
          icon: groupData['icon'] ?? "",
          isGroup: true,
          participants: List<String>.from(groupData['members'] ?? memberIds),
          permissions: [widget.currentUserId],
          time: DateTime.now().toIso8601String(),
          currentMessage: "",
          status: "admin",
          isOnline: false,
          lastSeen: "",
          createdBy: widget.currentUserId,
        );
        Navigator.pop(context, newGroup);
      } else
        throw Exception();
    } catch (e) {
      _showCriticalError("فشل إنشاء المجموعة: $e");
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _pickGroupImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _groupImageBytes = bytes);
    }
  }

  void _refreshGroupData() {}

  // ==================== واجهة المجموعة الرئيسية ====================
  Widget _buildGroupChatUI() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imagePath =
        isDark ? 'assets/theams/darkmode.png' : 'assets/theams/lightmode.png';
    final loadingColor = isDark ? Colors.white : const Color(0xFFE0E0E0);
    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFE5ECE1),
      appBar: isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: isLoadingMessages
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  loadingColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "جاري تحميل الرسائل...",
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ValueListenableBuilder<List<Map<String, dynamic>>>(
                        valueListenable: _messagesNotifier,
                        builder: (context, messages, child) {
                          return ListView.builder(
                            reverse: true,
                            controller: _scrollController,
                            addAutomaticKeepAlives: false,
                            cacheExtent: 500,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final msg = messages[index];
                              return GestureDetector(
                                onTapDown: (TapDownDetails details) {
                                  _currentTapPosition = details.globalPosition;
                                },
                                onLongPress: () {
                                  HapticFeedback.lightImpact();
                                  _showOptionsPopupMenu(
                                    context,
                                    msg,
                                    _currentTapPosition,
                                  );
                                },
                                child: _buildMessageBubble(msg, index),
                              );
                            },
                          );
                        },
                      ),
              ),
              RepaintBoundary(
                child: _CustomMessageInput(
                  isChatLocked: _isChatLocked,
                  isAdmin: isAdmin,
                  onSendTextMessage: _sendGroupMessage,
                  onAttachPressed: _showAttachSheet,
                  onCameraPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(
                          chatId: currentGroup!.id,
                          currentUserId: widget.currentUserId,
                          socket: socket,
                        ),
                      ),
                    );
                    if (result != null && result is Uint8List)
                      _showPreviewFromCamera(result);
                  },
                  controller: _messageController,
                  currentGroupId: currentGroup!.id,
                  currentUserId: widget.currentUserId,
                  baseUrl: widget.baseUrl,
                  socket: socket,
                  onNewMessage: (newMsg) {
                    setState(() {
                      _messages.insert(0, newMsg);
                      _messagesNotifier.value = _messages;
                    });
                    _autoScrollToLatest();
                  },
                ),
              ),
              const SizedBox(height: 4),
              _buildReplyBar(),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return isCreationMode ? _buildCreationUI() : _buildGroupChatUI();
  }
}

// ============================================================
//  GroupMembersPage - (بدون تغيير)
// ============================================================
class GroupMembersPage extends StatefulWidget {
  final ChatModel currentGroup;
  final String currentUserId;
  final String baseUrl;
  final IO.Socket socket;
  final VoidCallback onGroupDeleted;
  final ValueChanged<bool> onLockChanged;
  final VoidCallback onClearChatLocally;
  const GroupMembersPage({
    Key? key,
    required this.currentGroup,
    required this.currentUserId,
    required this.baseUrl,
    required this.socket,
    required this.onGroupDeleted,
    required this.onLockChanged,
    required this.onClearChatLocally,
  }) : super(key: key);

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

// ... باقي الكود (GroupMembersPage, _GroupSettingsDialog, _VideoPlayerScreen) كما هو بدون تغيير
class _GroupMembersPageState extends State<GroupMembersPage> {
  late ChatModel _currentGroup;
  late bool _isAdmin;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.currentGroup;
    _isAdmin = widget.currentGroup.createdBy == widget.currentUserId ||
        widget.currentGroup.permissions.contains(widget.currentUserId);
  }

  Future<List<Map<String, dynamic>>> _getGroupMembersWithDetails() async {
    final List<Map<String, dynamic>> members = [];
    for (final uid in _currentGroup.participants) {
      final details = await _getMemberDetails(uid);
      String role = uid == _currentGroup.createdBy
          ? "creator"
          : (_currentGroup.permissions.contains(uid) ? "admin" : "member");
      members.add({
        'user_id': uid,
        'username': details['name'],
        'avatar': details['avatar'],
        'role': role,
      });
    }
    members.sort(
      (a, b) => {'creator': 0, 'admin': 1, 'member': 2}[a['role']]!.compareTo(
        {'creator': 0, 'admin': 1, 'member': 2}[b['role']]!,
      ),
    );
    return members;
  }

  Future<Map<String, String>> _getMemberDetails(String userId) async {
    if (userId == widget.currentUserId) return {'name': 'أنت', 'avatar': ''};
    try {
      final response = await http.get(
        Uri.parse("${widget.baseUrl}/users/$userId"),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'name': data['username'] ?? 'مستخدم',
          'avatar': data['avatar_url'] ?? '',
        };
      }
    } catch (_) {}
    return {'name': 'مستخدم', 'avatar': ''};
  }

  String? _getFullAvatarUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    String clean = url.startsWith('/') ? url.substring(1) : url;
    if (clean.startsWith('uploads_camera/'))
      clean = clean.substring('uploads_camera/'.length);
    if (clean.startsWith('uploads/'))
      clean = clean.substring('uploads/'.length);
    return "${widget.baseUrl}/uploads/$clean";
  }

  Future<void> _editGroupName() async {
    final controller = TextEditingController(text: _currentGroup.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تعديل اسم المجموعة"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "الاسم الجديد"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
    if (newName != null &&
        newName.isNotEmpty &&
        newName != _currentGroup.name) {
      try {
        await http.put(
          Uri.parse("${widget.baseUrl}/groups/${_currentGroup.id}"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "name": newName,
            "requester_id": widget.currentUserId,
          }),
        );
        setState(() => _currentGroup = _currentGroup.copyWith(name: newName));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("تم تحديث الاسم")));
      } catch (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("فشل تحديث الاسم")));
      }
    }
  }

  Future<void> _editGroupImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("${widget.baseUrl}/chat/upload"),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'chat_file',
          bytes,
          filename: 'group_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final imageUrl = jsonDecode(response.body)['url'];
        await http.put(
          Uri.parse("${widget.baseUrl}/groups/${_currentGroup.id}"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "icon": imageUrl,
            "requester_id": widget.currentUserId,
          }),
        );
        setState(() => _currentGroup = _currentGroup.copyWith(icon: imageUrl));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("تم تحديث الصورة")));
      }
    }
  }

  Future<void> _addNewMembers() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectMembers(
          currentUserId: widget.currentUserId,
          multiSelect: true,
        ),
      ),
    );
    List<String> newMemberIds = [];
    if (result != null && result is List<ChatModel>)
      newMemberIds = result.map((m) => m.id).toList();
    else if (result != null && result is List<String>)
      newMemberIds = result;
    else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("لم يتم اختيار أي أعضاء")));
      return;
    }
    if (newMemberIds.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse("${widget.baseUrl}/groups/add_members"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "group_id": _currentGroup.id,
          "member_ids": newMemberIds,
          "requester_id": widget.currentUserId,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _refreshGroupData();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("تمت إضافة الأعضاء")));
      } else
        throw Exception();
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("فشل إضافة الأعضاء")));
    }
  }

  Future<void> _refreshGroupData() async {
    try {
      final response = await http.get(
        Uri.parse("${widget.baseUrl}/groups?user_id=${widget.currentUserId}"),
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        final updated = data.firstWhere(
          (g) => g['id'] == _currentGroup.id,
          orElse: () => null,
        );
        if (updated != null) {
          final admins = <String>[];
          if (updated['created_by'] != null) admins.add(updated['created_by']);
          if (updated['admins'] != null)
            admins.addAll(List<String>.from(updated['admins']));
          setState(() {
            _currentGroup = _currentGroup.copyWith(
              participants: List<String>.from(updated['participants'] ?? []),
              name: updated['name'] ?? _currentGroup.name,
              icon: updated['icon'] ?? _currentGroup.icon,
              permissions: admins,
            );
          });
          _isAdmin = _currentGroup.createdBy == widget.currentUserId ||
              _currentGroup.permissions.contains(widget.currentUserId);
        }
      }
    } catch (_) {}
  }

  Future<void> _kickMember(String userId, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("طرد عضو"),
        content: Text("هل أنت متأكد من طرد $userName من المجموعة؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("طرد", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await http.post(
          Uri.parse("${widget.baseUrl}/groups/remove_member"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "group_id": _currentGroup.id,
            "user_id": userId,
            "requester_id": widget.currentUserId,
          }),
        );
        await _refreshGroupData();
        if (userId == widget.currentUserId) {
          Navigator.pop(context);
          widget.onGroupDeleted();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("تم طرد العضو")));
        }
      } catch (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("فشل طرد العضو")));
      }
    }
  }

  Future<void> _promoteToAdmin(String userId, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ترقية عضو"),
        content: Text("هل أنت متأكد من ترقية $userName إلى مشرف؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("ترقية"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await http.post(
          Uri.parse("${widget.baseUrl}/groups/promote_admin"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "group_id": _currentGroup.id,
            "user_id": userId,
            "requester_id": widget.currentUserId,
          }),
        );
        await _refreshGroupData();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("تمت الترقية إلى مشرف")));
      } catch (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("فشل الترقية")));
      }
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (_) => _GroupSettingsDialog(
        currentGroup: _currentGroup,
        currentUserId: widget.currentUserId,
        baseUrl: widget.baseUrl,
        socket: widget.socket,
        onGroupDeleted: widget.onGroupDeleted,
        onLockChanged: (v) {
          widget.onLockChanged(v);
          _refreshGroupData();
        },
        onClearChat: widget.onClearChatLocally,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text("أعضاء المجموعة"),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        foregroundColor: colorScheme.onSurface,
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: colorScheme.onSurface),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _isAdmin ? _editGroupImage : null,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: colorScheme.primary.withOpacity(0.1),
                    backgroundImage: _currentGroup.icon.isNotEmpty
                        ? NetworkImage(_getFullAvatarUrl(_currentGroup.icon)!)
                        : null,
                    child: _currentGroup.icon.isEmpty
                        ? Icon(
                            Icons.group,
                            size: 45,
                            color: colorScheme.primary,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _currentGroup.name,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isAdmin) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                Icons.edit,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                              onPressed: () async {
                                await _editGroupName();
                                setState(() {});
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${_currentGroup.participants.length} عضو",
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (_isAdmin)
                  IconButton(
                    icon: Icon(Icons.person_add, color: colorScheme.primary),
                    onPressed: _addNewMembers,
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _getGroupMembersWithDetails(),
              builder: (ctx, snap) {
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final members = snap.data!;
                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final m = members[i];
                    final isCreator = m['role'] == 'creator';
                    final isAdminMember = m['role'] == 'admin';
                    final isMe = m['user_id'] == widget.currentUserId;
                    String roleText =
                        isCreator ? "المنشئ" : (isAdminMember ? "مشرف" : "عضو");
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primary.withOpacity(0.1),
                        backgroundImage: (m['avatar'] != null &&
                                m['avatar'].toString().isNotEmpty)
                            ? NetworkImage(_getFullAvatarUrl(m['avatar'])!)
                            : null,
                        child: (m['avatar'] == null ||
                                m['avatar'].toString().isEmpty)
                            ? Text(
                                m['username'][0].toUpperCase(),
                                style: TextStyle(color: colorScheme.primary),
                              )
                            : null,
                      ),
                      title: Text(
                        m['username'],
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      subtitle: Text(
                        roleText,
                        style: TextStyle(
                          color: isCreator
                              ? Colors.amber
                              : (isAdminMember
                                  ? Colors.blue
                                  : colorScheme.onSurfaceVariant),
                        ),
                      ),
                      onTap: () {
                        if (_isAdmin && !isCreator && !isMe && !isAdminMember) {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: colorScheme.surface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                            ),
                            builder: (_) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: Icon(
                                      Icons.admin_panel_settings,
                                      color: Colors.orange,
                                    ),
                                    title: Text(
                                      "ترقية إلى مشرف",
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _promoteToAdmin(
                                        m['user_id'],
                                        m['username'],
                                      );
                                    },
                                  ),
                                  ListTile(
                                    leading: Icon(
                                      Icons.exit_to_app,
                                      color: Colors.red,
                                    ),
                                    title: Text(
                                      "طرد من المجموعة",
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _kickMember(m['user_id'], m['username']);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  _GroupSettingsDialog - (بدون تغيير)
// ============================================================
class _GroupSettingsDialog extends StatefulWidget {
  final ChatModel currentGroup;
  final String currentUserId;
  final String baseUrl;
  final IO.Socket socket;
  final VoidCallback onGroupDeleted;
  final ValueChanged<bool> onLockChanged;
  final VoidCallback onClearChat;
  const _GroupSettingsDialog({
    Key? key,
    required this.currentGroup,
    required this.currentUserId,
    required this.baseUrl,
    required this.socket,
    required this.onGroupDeleted,
    required this.onLockChanged,
    required this.onClearChat,
  }) : super(key: key);

  @override
  State<_GroupSettingsDialog> createState() => _GroupSettingsDialogState();
}

class _GroupSettingsDialogState extends State<_GroupSettingsDialog> {
  late bool _isChatLocked;
  late bool _isAdmin;

  @override
  void initState() {
    super.initState();
    _isChatLocked = false;
    _isAdmin = widget.currentGroup.createdBy == widget.currentUserId ||
        widget.currentGroup.permissions.contains(widget.currentUserId);
    _loadLockState();
  }

  Future<void> _loadLockState() async {
    try {
      final response = await http.get(
        Uri.parse("${widget.baseUrl}/groups?user_id=${widget.currentUserId}"),
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        final updated = data.firstWhere(
          (g) => g['id'] == widget.currentGroup.id,
          orElse: () => null,
        );
        if (updated != null) {
          setState(() => _isChatLocked = updated['locked'] ?? false);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleChatLock(bool newValue) async {
    try {
      await http.put(
        Uri.parse("${widget.baseUrl}/groups/${widget.currentGroup.id}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "locked": newValue,
          "requester_id": widget.currentUserId,
        }),
      );
      setState(() => _isChatLocked = newValue);
      widget.onLockChanged(newValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newValue ? "تم قفل الدردشة" : "تم فتح الدردشة")),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("فشل تحديث حالة القفل"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف المجموعة"),
        content: const Text(
          "هل أنت متأكد من حذف المجموعة نهائياً؟ هذا الإجراء لا يمكن التراجع عنه.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await http.delete(
          Uri.parse("${widget.baseUrl}/groups/${widget.currentGroup.id}"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"requester_id": widget.currentUserId}),
        );
        Navigator.pop(context);
        widget.onGroupDeleted();
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("فشل حذف المجموعة"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("مغادرة المجموعة"),
        content: const Text("هل أنت متأكد من مغادرة المجموعة؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("مغادرة", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await http.post(
          Uri.parse("${widget.baseUrl}/groups/leave"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "group_id": widget.currentGroup.id,
            "user_id": widget.currentUserId,
          }),
        );
        Navigator.pop(context);
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("تمت مغادرة المجموعة")));
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("فشل مغادرة المجموعة"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      title: Text(
        "إعدادات المجموعة",
        textAlign: TextAlign.center,
        style: TextStyle(color: colorScheme.onSurface),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isAdmin)
              SwitchListTile(
                title: Text(
                  "قفل الدردشة",
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                subtitle: Text(
                  "منع الأعضاء العاديين من الإرسال",
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                value: _isChatLocked,
                onChanged: _toggleChatLock,
                secondary: Icon(Icons.lock_outline, color: colorScheme.primary),
                activeColor: colorScheme.primary,
              ),
            if (_isAdmin) const Divider(),
            ListTile(
              leading: Icon(Icons.delete_sweep, color: Colors.orange),
              title: Text(
                "مسح الدردشة",
                style: TextStyle(color: colorScheme.onSurface),
              ),
              subtitle: Text(
                "حذف جميع الرسائل من جهازك فقط",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onClearChat();
              },
            ),
            const Divider(),
            if (_isAdmin)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  "حذف المجموعة",
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => _deleteGroup(),
              ),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.orange),
              title: const Text(
                "مغادرة المجموعة",
                style: TextStyle(color: Colors.orange),
              ),
              onTap: () => _leaveGroup(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            "إغلاق",
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ============================================================
//  _VideoPlayerScreen - (بدون تغيير)
// ============================================================
class _VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String messageId;
  final Duration initialPosition;
  final bool wasPlaying;
  const _VideoPlayerScreen({
    Key? key,
    required this.videoUrl,
    required this.messageId,
    required this.initialPosition,
    required this.wasPlaying,
  }) : super(key: key);

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isCameraVideo = false;
  bool _isPlaying = false;
  bool _showControls = true;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    _isCameraVideo = widget.videoUrl.contains('/uploads_camera/');
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _totalDuration = _controller.value.duration;
      });
      await _controller.seekTo(widget.initialPosition);
      if (widget.wasPlaying) {
        await _controller.play();
        _isPlaying = true;
      } else {
        _isPlaying = false;
      }
      _controller.addListener(_updateProgress);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isPlaying) setState(() => _showControls = false);
      });
    } catch (error) {
      print("Video player error: $error");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("فشل تحميل الفيديو")));
      }
    }
  }

  void _updateProgress() {
    if (!mounted) return;
    setState(() {
      _currentPosition = _controller.value.position;
      _isPlaying = _controller.value.isPlaying;
    });
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _controller.pause();
    } else {
      if (_currentPosition >= _totalDuration)
        await _controller.seekTo(Duration.zero);
      await _controller.play();
    }
    setState(() => _isPlaying = !_isPlaying);
    _showControlsTemporarily();
  }

  void _restartVideo() async {
    await _controller.seekTo(Duration.zero);
    if (!_isPlaying) {
      await _controller.play();
      setState(() => _isPlaying = true);
    }
    setState(() {
      _currentPosition = Duration.zero;
      _showControls = true;
    });
    _showControlsTemporarily();
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return "0:00";
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller.pause();
    _controller.removeListener(_updateProgress);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(
              _isCameraVideo ? Icons.camera_alt : Icons.video_library,
              color: _isCameraVideo
                  ? (isDark ? const Color(0xFF00A884) : const Color(0xFF1E88E5))
                  : Colors.blue,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              _isCameraVideo ? "فيديو من الكاميرا" : "فيديو من المعرض",
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: _showControlsTemporarily,
        child: Stack(
          children: [
            if (!_isInitialized)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      "جاري تحميل الفيديو...",
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              )
            else
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
            if (_isInitialized)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Spacer(),
                      if (!_isPlaying || _showControls)
                        Center(
                          child: GestureDetector(
                            onTap: _togglePlayPause,
                            child: AnimatedOpacity(
                              opacity:
                                  (!_isPlaying || _showControls) ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.95),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isPlaying
                                      ? Icons.pause
                                      : (_currentPosition >= _totalDuration &&
                                              _totalDuration > Duration.zero)
                                          ? Icons.replay
                                          : Icons.play_arrow,
                                  color: isDark
                                      ? const Color(0xFF42A5F5)
                                      : const Color(0xFF1E88E5),
                                  size: 50,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: _restartVideo,
                                    icon: const Icon(
                                      Icons.replay,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  Expanded(
                                    child: VideoProgressIndicator(
                                      _controller,
                                      allowScrubbing: true,
                                      colors: const VideoProgressColors(
                                        playedColor: Color(0xFF075E54),
                                        bufferedColor: Colors.white38,
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      "${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
