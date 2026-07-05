import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sdp_transform/sdp_transform.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:fitst_app/CustomUI/ProfilePage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:fitst_app/screens/chat_actions/location_picker_page.dart';
import 'package:fitst_app/screens/chat_actions/CameraScreen.dart';
import 'package:fitst_app/screens/chat_actions/video_player_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fitst_app/screens/chat_actions/UniversalAudioPlayer.dart';
import 'package:fitst_app/Pages/ChatPageForForward.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

// WebRTC imports
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:fitst_app/Call/incoming_call_overlay.dart';
import 'package:fitst_app/main.dart';
// ✅ استيراد call_manager (يحتوي على CallManager و CallState)
import 'package:fitst_app/Call/call_manager.dart';
// ✅ استيراد call_screen مع إخفاء CallState لتجنب التعارض
import 'package:fitst_app/Call/call_screen.dart' hide CallState;

// ==================== VideoPlayerManager ====================
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

// ==================== IndividualPage ====================
class IndividualPage extends StatefulWidget {
  final ChatModel chatmodel;
  final String currentUserId;
  final IO.Socket? existingSocket;
  final Map<String, dynamic>? forwardingMessage;

  const IndividualPage({
    Key? key,
    required this.chatmodel,
    required this.currentUserId,
    this.existingSocket,
    this.forwardingMessage,
  }) : super(key: key);

  @override
  State<IndividualPage> createState() => _IndividualPageState();
}

class _IndividualPageState extends State<IndividualPage> {
  // ==================== متغيرات الاتصال والشات ====================
  IO.Socket? socket;
  List<Map<String, dynamic>> _messages = [];
  String? chatId;
  bool isLoading = true;
  bool _isChatReady = false;
  final ScrollController _scrollController = ScrollController();
  bool isOnline = false;
  String lastSeen = "";
  Timer? _pingTimer;
  bool _isDisposed = false;
  bool _callEndHandled = false;
  String? _currentCallId;
  String? _incomingCallerId;
  String? _incomingCallId;

  // ==================== الردود ====================
  Map<String, dynamic>? _replyingToMessage;
  bool get _isReplying => _replyingToMessage != null;

  // ==================== إعادة التوجيه ====================
  late SharedPreferences _prefs;
  Set<String> _forwardedMessageIds = {};

  // ==================== التسجيل الصوتي ====================
  FlutterSoundRecorder? _voiceRecorder;
  bool _isRecordingVoice = false;
  Duration _voiceDuration = Duration.zero;
  Timer? _voiceTimer;
  DateTime? _voiceStartTime;
  List<double> _voiceWaveLevels = List.filled(40, 0.0);
  Timer? _waveTimer;
  bool _isDraggingToCancel = false;
  Offset _dragStartPosition = Offset.zero;
  String? _currentVoicePath;
  bool _isVoiceLocked = false;
  bool _isSwipedToCancel = false;
  bool _isSwipedToLock = false;

  // ==================== الإدخال ====================
  final TextEditingController _controller = TextEditingController();
  bool _showSendButton = false;

  // ==================== وضع التحديد المتعدد ====================
  Set<String> selectedMessageIds = {};
  bool isSelectionMode = false;
  String _selectedAction = '';

  // ==================== متغيرات المكالمات ====================
  bool _isCalling = false;
  String? _callingUserName;
  String? _callingUserImage;
  String _callStatusText = "";
  DateTime? _callStartTime;
  bool _isCallAnswered = false;
  bool _isIncomingCall = false;
  String? _callEndReason;

  // ==================== مرجع حوار المكالمة الواردة ====================
  BuildContext? _dialogContext;
  bool _isDialogShowing = false;

  // ==================== عنوان السيرفر الذكي ====================
  String _serverUrl = '';

  String get serverUrl {
    if (_serverUrl.isNotEmpty) return _serverUrl;
    return _getDefaultServerUrl();
  }

  String _getDefaultServerUrl() => ApiConfig.baseUrl;

  Future<void> _loadServerUrl() async {
    _prefs = await SharedPreferences.getInstance();
    final savedUrl = _prefs.getString('server_url') ?? '';
    setState(() => _serverUrl = savedUrl);
  }

  // ==================== دورة الحياة ====================
  @override
  void initState() {
    super.initState();
    _loadServerUrl().then((_) {
      _initSharedPrefs();
      isOnline = widget.chatmodel.isOnline;
      lastSeen = widget.chatmodel.lastSeen;
      _checkAndInitialize();
      _initRecorder();
      _setupGlobalCallListeners();

      if (widget.forwardingMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && chatId != null) {
              _showForwardConfirmation(widget.forwardingMessage!);
            } else {
              _showCriticalError("خطأ: لم يتم تحميل المحادثة بعد");
            }
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pingTimer?.cancel();
    _voiceTimer?.cancel();
    _waveTimer?.cancel();
    _voiceRecorder?.closeRecorder();
    _deleteVoiceFile();
    _scrollController.dispose();
    _dialogContext = null;
    _isDialogShowing = false;

    CallManager().removeStateListener(_onCallStateChanged);
    CallManager().callService?.onStateChanged = null;

    if (widget.existingSocket == null) {
      socket?.emit("logout", widget.currentUserId);
      socket?.disconnect();
    }
    VideoPlayerManager().stopAllVideos();
    super.dispose();
  }

  // ==================== تهيئة المكالمات العامة ====================
  void _setupGlobalCallListeners() {
    CallManager().onIncomingCall = (data) async {
      if (chatId == null) {
        print('📞 [Call] chatId غير جاهز، جاري إنشاء المحادثة...');
        try {
          final response = await http.post(
            Uri.parse("$serverUrl/conversations/get_or_create"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "current_user_id": widget.currentUserId,
              "other_user_id": data['callerId'] ?? widget.chatmodel.id,
            }),
          );
          final body = jsonDecode(response.body);
          chatId = body['id'];
          print('🟢 [Call] تم إنشاء chatId: $chatId');
          setState(() => _isChatReady = true);
        } catch (e) {
          print('❌ [Call] فشل إنشاء المحادثة: $e');
          _showCriticalError('حدث خطأ أثناء تهيئة المحادثة');
          return;
        }
      }

      _incomingCallerId = data['callerId'];
      _incomingCallId = data['callId'] ?? 'unknown';
      _callEndReason = null;
      _currentCallId = data['callId'] ?? 'unknown';
      print('📞 استقبال مكالمة واردة من: ${data['callerName']}');

      if (_dialogContext != null) {
        try {
          Navigator.pop(_dialogContext!);
        } catch (e) {}
        _dialogContext = null;
        _isDialogShowing = false;
      }

      if (_isDialogShowing) {
        print('⚠️ حوار مكالمة قيد العرض بالفعل، تجاهل المكالمة الجديدة');
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _isDialogShowing = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext ctx) {
            _dialogContext = ctx;
            return IncomingCallOverlay(
              callerName: data['callerName'] ?? 'مستخدم',
              callerAvatar: data['callerAvatar'] ?? widget.chatmodel.icon,
              isVideo: data['isVideo'] ?? false,
              serverUrl: serverUrl,
              onAccept: () {
                _isCallAnswered = true;
                _isIncomingCall = true;
                _callStartTime = DateTime.now();
                Navigator.pop(ctx);
                _dialogContext = null;
                _isDialogShowing = false;
                CallManager().acceptCall();
              },
              onReject: () {
                _isCallAnswered = false;
                _isIncomingCall = true;
                _callEndReason = 'rejected';
                Navigator.pop(ctx);
                _dialogContext = null;
                _isDialogShowing = false;
                CallManager().rejectCall();
                _callEndHandled = true;
                setState(() {
                  _isCalling = false;
                  _callStatusText = "انتهت";
                });
              },
            );
          },
        ).then((_) {
          _dialogContext = null;
          _isDialogShowing = false;
        });
      });
    };

    CallManager().onCallStarted = (callService) {
      if (_isDisposed || !mounted) return;
      final name = callService.callerName.isNotEmpty
          ? callService.callerName
          : widget.chatmodel.name;
      final avatar = callService.callerAvatar ?? widget.chatmodel.icon;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callService: callService,
            callerName: name,
            callerAvatar: avatar,
            serverUrl: serverUrl,
          ),
        ),
      ).then((_) {
        if (mounted) setState(() => _isCalling = false);
      });
    };
  }

  void _setCallStateListener() {
    CallManager().removeStateListener(_onCallStateChanged);
    CallManager().addStateListener(_onCallStateChanged);
  }

  void _onCallStateChanged(CallState state) {
    if (_isDisposed || !mounted) return;
    print("📞 Call state changed: $state");

    switch (state) {
      case CallState.ringing:
        setState(() {
          _isCalling = true;
          _callStatusText = "رنين...";
        });
        break;

      case CallState.connected:
        _isCallAnswered = true;
        _callStartTime ??= DateTime.now();
        setState(() {
          _isCalling = true;
          _callStatusText = "متصل";
        });
        break;

      case CallState.ended:
      case CallState.idle:
        // ✅ إغلاق حوار المكالمة الواردة مع منع التكرار
        if (_isDialogShowing && _dialogContext != null) {
          print('📞 محاولة إغلاق حوار المكالمة الواردة...');
          try {
            Navigator.pop(_dialogContext!);
            print('✅ تم إغلاق الحوار باستخدام _dialogContext');
          } catch (e) {
            print('⚠️ فشل إغلاق الحوار باستخدام _dialogContext: $e');
            // محاولة بديلة
            try {
              Navigator.of(context, rootNavigator: true).pop();
              print('✅ تم إغلاق الحوار باستخدام rootNavigator');
            } catch (e2) {
              print('⚠️ فشل إغلاق الحوار باستخدام rootNavigator: $e2');
            }
          }
          _dialogContext = null;
          _isDialogShowing = false;
        }

        // حساب المدة وإعادة التعيين
        int duration = 0;
        if (_callStartTime != null && _isCallAnswered) {
          duration = DateTime.now().difference(_callStartTime!).inSeconds;
        }
        _callStartTime = null;
        _isCallAnswered = false;
        _isIncomingCall = false;
        _callEndReason = null;
        _currentCallId = null;

        setState(() {
          _isCalling = false;
          _callStatusText = "انتهت";
        });

        if (duration > 0) {
          _showCriticalError("✅ انتهت المكالمة (المدة: $duration ثانية)");
        } else {
          if (_callEndReason == 'rejected') {
            _showCriticalError("❌ تم رفض المكالمة");
          } else if (_callEndReason == 'busy') {
            _showCriticalError("❌ المستخدم مشغول");
          } else if (_callEndReason == 'cancelled' ||
              _callEndReason == 'إلغاء المكالمة') {
            _showCriticalError("⛔ تم إلغاء المكالمة");
          }
        }
        break;

      case CallState.connecting:
        setState(() => _callStatusText = "جاري التوصيل...");
        break;

      default:
        break;
    }
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
    if (ids != null) _forwardedMessageIds = ids.toSet();
  }

  void _saveForwardedId(String messageId) {
    _forwardedMessageIds.add(messageId);
    _prefs.setStringList(
      'forwarded_messages_${widget.currentUserId}',
      _forwardedMessageIds.toList(),
    );
  }

  void _checkAndInitialize() {
    if (widget.currentUserId.isEmpty || widget.chatmodel.id.isEmpty) {
      _showCriticalError("خطأ في البيانات");
      setState(() => isLoading = false);
      return;
    }
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    try {
      final response = await http.post(
        Uri.parse("$serverUrl/conversations/get_or_create"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "current_user_id": widget.currentUserId,
          "other_user_id": widget.chatmodel.id,
        }),
      );
      final body = jsonDecode(response.body);
      chatId = body['id'];
      print("🟢 تم تعيين chatId: $chatId");
      setState(() => _isChatReady = true);

      if (widget.existingSocket != null) {
        socket = widget.existingSocket;
        socket?.emit("signin", widget.currentUserId);
        if (CallManager().isInitialized == false) {
          CallManager().initialize(socket!, widget.currentUserId);
        }
        socket?.emit("join_chat", chatId);
        _setupSocketListeners();
      } else {
        _connectSocket();
      }

      _setCallStateListener();
      _loadMessages();
      _fetchUserStatus();
    } catch (e) {
      _showCriticalError("فشل الاتصال بالسيرفر");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchUserStatus() async {
    try {
      final res = await http.get(Uri.parse("$serverUrl/users"));
      if (res.statusCode == 200) {
        final List users = jsonDecode(res.body);
        final user = users.firstWhere(
          (u) => u['id'].toString() == widget.chatmodel.id.toString(),
          orElse: () => null,
        );
        if (user != null && mounted) {
          setState(() {
            isOnline = user['is_online'] == true;
            lastSeen = user['last_seen']?.toString() ?? "";
          });
        }
      }
    } catch (_) {}
    socket?.emit("get_user_status", widget.chatmodel.id);
  }

  void _setupSocketListeners() {
    if (socket == null) return;
    socket!.off('message');
    socket!.off('user_status');
    socket!.off('message_deleted');

    socket!.on('message', _onMessageReceived);
    socket!.on("user_status", _onUserStatus);
    socket!.on("message_deleted", _onMessageDeleted);
  }

  void _connectSocket() {
    if (socket != null) return;

    socket = IO.io(
      serverUrl,
      IO.OptionBuilder().setTransports(['websocket']).build(),
    );

    if (CallManager().isInitialized == false) {
      CallManager().initialize(socket!, widget.currentUserId);
    }

    socket!.on('message', _onMessageReceived);
    socket!.on("user_status", _onUserStatus);
    socket!.on("message_deleted", _onMessageDeleted);
    _setupSocketListeners();

    socket!.onDisconnect((_) {
      if (mounted) {
        setState(() => isOnline = false);
        print("⚠️ Socket disconnected, attempting reconnect...");
        Future.delayed(const Duration(seconds: 2), () {
          if (socket != null && !socket!.connected) socket!.connect();
        });
      }
    });

    socket!.connect();

    socket!.onConnect((_) {
      print(
          "✅ Socket connected, sending signin with userId: ${widget.currentUserId}");
      socket!.emit("signin", widget.currentUserId);

      if (chatId != null) {
        socket!.emit("join_chat", chatId);
      }

      _fetchUserStatus();
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        socket?.emit("ping");
      });
    });
  }

  // ==================== استقبال الرسائل ====================
  void _onMessageReceived(dynamic data) {
    if (!mounted) return;
    if (data['chat_id'] != null &&
        chatId != null &&
        data['chat_id'].toString() == chatId) {
      setState(() {
        if (data['type'] == 'call_log') {
          _messages.removeWhere(
              (msg) => msg['is_temp'] == true && msg['type'] == 'call_log');
          data.remove('is_temp');
          _messages.insert(0, Map<String, dynamic>.from(data));
          _autoScrollToLatest();
          return;
        }

        final exists = _messages.any((msg) => msg['id'] == data['id']);
        if (!exists) {
          final msgId = data['id'].toString();
          if (_forwardedMessageIds.contains(msgId) ||
              data['original_sender'] != null) {
            data['forwarded'] = true;
          } else {
            data['forwarded'] = data['forwarded'] ?? false;
          }

          final replied = data['replied_message'];
          if (replied != null && replied is Map<String, dynamic>) {
            data['reply_to'] = {
              'message_id': data['reply_to_message_id'] ?? '',
              'message_text': replied['message'] ?? '',
              'sender_name': replied['sender_id'] == widget.currentUserId
                  ? 'أنت'
                  : (replied['sender_name'] ?? 'مستخدم'),
              'message_type': _getTypeFromMessage(replied['message'] ?? ''),
              'duration': replied['duration'] ?? 0,
            };
          } else {
            data.remove('reply_to');
          }
          _messages.insert(0, Map<String, dynamic>.from(data));
          _autoScrollToLatest();
        }
      });
    }
  }

  void _onUserStatus(dynamic data) {
    if (!mounted) return;
    if (data["user_id"]?.toString() == widget.chatmodel.id.toString()) {
      setState(() {
        isOnline = data["is_online"] == true;
        lastSeen = data["last_seen"]?.toString() ?? "";
      });
    }
  }

  void _onMessageDeleted(dynamic data) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((m) => m['id'].toString() == data.toString());
    });
  }

  Future<void> _loadMessages() async {
    if (chatId == null) return;
    final res = await http.get(
      Uri.parse("$serverUrl/messages/$chatId?user_id=${widget.currentUserId}"),
    );
    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body);
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
          message['reply_to'] = {
            'message_id': message['reply_to_message_id'] ?? '',
            'message_text': replied['message'] ?? '',
            'sender_name': replied['sender_id'] == widget.currentUserId
                ? 'أنت'
                : (replied['sender_name'] ?? 'مستخدم'),
            'message_type': _getTypeFromMessage(replied['message'] ?? ''),
            'duration': replied['duration'] ?? 0,
          };
        } else {
          message.remove('reply_to');
        }
        loadedMessages.add(message);
      }
      setState(() {
        _messages = loadedMessages;
      });
    }
  }

  // ==================== إرسال الرسائل ====================
  void _sendMessage() {
    print("🟢 _sendMessage called, chatId=$chatId, _isChatReady=$_isChatReady");
    if (!_isChatReady || chatId == null) {
      _showCriticalError("المحادثة ليست جاهزة بعد، انتظر قليلاً");
      return;
    }
    if (_controller.text.trim().isEmpty) return;
    final msgText = _controller.text.trim();
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
      "chat_id": chatId,
      "sender_id": widget.currentUserId,
      "message": msgText,
      "created_at": DateTime.now().toIso8601String(),
      "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
      "reply_to": replyPreview,
    };
    setState(() {
      _messages.insert(0, tempMsg);
      _controller.clear();
      _showSendButton = false;
      _cancelReply();
    });
    _autoScrollToLatest();
    socket?.emit("message", {
      "chat_id": chatId,
      "sender_id": widget.currentUserId,
      "message": msgText,
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
    final String previewText = _getMessagePreview({
      'message': replyTo['message_text'] ?? '',
      'type': replyTo['message_type'] ?? '',
      'duration': replyTo['duration'] ?? 0,
    });
    final String replySender = replyTo['sender_name'] ?? 'مستخدم';
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
                  previewText,
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

  // ==================== إعادة التوجيه ====================
  String _getMessagePreview(Map<String, dynamic> message) {
    final msgContent = message['message'] ?? '';
    final msgType = message['type'] ?? 'text';
    if (msgType == 'image') return '🖼️ صورة';
    if (msgType == 'video') return '🎥 فيديو';
    if (msgType == 'voice') return '🎤 رسالة صوتية';
    if (msgContent.startsWith('LOCATION:')) return '📍 موقع';
    String preview = msgContent;
    if (preview.length > 50) preview = preview.substring(0, 50) + '...';
    return preview;
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
              'إلى: ${widget.chatmodel.name}',
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
    if (chatId == null) {
      _showCriticalError('خطأ: معرف المحادثة غير جاهز');
      return;
    }
    final bool isGroup = widget.chatmodel.isGroup == true;
    final String chatType = isGroup ? 'group' : 'private';
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
      "chat_id": chatId!,
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
    setState(() => _messages.insert(0, tempMessage));
    _autoScrollToLatest();

    try {
      final response = await http.post(
        Uri.parse("$serverUrl/messages/forward"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "chat_id": chatId!,
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
              }
            });
          } else {
            setState(() => _messages.removeWhere((msg) => msg['id'] == tempId));
            await _loadMessages();
          }
          _showCriticalError('✅ تم إعادة التوجيه بنجاح');
        } else {
          throw Exception(resData['error'] ?? 'فشل الإرسال');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _messages.removeWhere((msg) => msg['id'] == tempId));
      _showCriticalError('❌ فشل إعادة التوجيه: ${e.toString()}');
    }
  }

  // ==================== دوال المكالمات ====================
  Future<void> _startCall(bool video) async {
    if (chatId == null) {
      _showCriticalError("المحادثة غير جاهزة");
      return;
    }
    if (CallManager().isInCall) {
      _showCriticalError("أنت في مكالمة حالياً");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    String currentUserName = prefs.getString('username') ?? 'مستخدم';
    String? currentUserAvatar = prefs.getString('user_file') ??
        prefs.getString('avatar') ??
        prefs.getString('avatar_url');

    print('📸 currentUserAvatar = $currentUserAvatar');

    final String tempCallId = 'call_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _isCalling = true;
      _isIncomingCall = false;
      _callEndHandled = false;
      _callingUserName = widget.chatmodel.name;
      _callingUserImage = _getFullAvatarUrl(widget.chatmodel.icon);
      _callStatusText = "اتصال...";
      _callStartTime = DateTime.now();
      _isCallAnswered = false;
      _callEndReason = null;
      _currentCallId = tempCallId;
    });

    try {
      if (!kIsWeb) {
        var micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          _showCriticalError("الرجاء السماح بالوصول إلى الميكروفون");
          if (mounted) setState(() => _isCalling = false);
          return;
        }
        if (video) {
          var camStatus = await Permission.camera.request();
          if (!camStatus.isGranted) {
            _showCriticalError("الرجاء السماح بالوصول إلى الكاميرا");
            if (mounted) setState(() => _isCalling = false);
            return;
          }
        }
      } else {
        try {
          await navigator.mediaDevices.getUserMedia({'audio': true});
          if (video) {
            await navigator.mediaDevices.getUserMedia({'video': true});
          }
        } catch (e) {
          _showCriticalError(
            "الرجاء السماح بالوصول إلى الميكروفون/الكاميرا في المتصفح",
          );
          if (mounted) setState(() => _isCalling = false);
          return;
        }
      }

      if (socket == null || !socket!.connected) {
        _showCriticalError("لا يوجد اتصال بالسيرفر");
        if (mounted) setState(() => _isCalling = false);
        return;
      }

      await CallManager().startCall(
        widget.chatmodel.id,
        video,
        chatId!,
        name: widget.chatmodel.name,
        avatar: widget.chatmodel.icon,
        myName: currentUserName,
        myAvatar: currentUserAvatar,
      );

      print('📞 _startCall: _currentCallId = $_currentCallId');
      if (_isDisposed || !mounted) return;
    } catch (e) {
      _showCriticalError("فشل بدء المكالمة: ${e.toString()}");
      if (mounted) setState(() => _isCalling = false);
      _callEndReason = 'failed';
    }
  }

  // ==================== التسجيل الصوتي ====================
  void _initRecorder() {
    _voiceRecorder = FlutterSoundRecorder();
    _voiceRecorder?.openRecorder();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Future<void> _startVoiceRecording() async {
    try {
      var status = await Permission.microphone.request();
      if (!status.isGranted) {
        _showCriticalError("الرجاء السماح بالوصول إلى الميكروفون");
        return;
      }

      HapticFeedback.mediumImpact();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'voice_$timestamp.aac';
      final directory = await getTemporaryDirectory();
      _currentVoicePath = '${directory.path}/$fileName';

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
        _isDraggingToCancel = false;
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
      _showCriticalError("حدث خطأ أثناء بدء التسجيل: $e");
    }
  }

  void _startWaveSimulation() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (_isRecordingVoice && mounted) {
        setState(() {
          for (int i = 0; i < _voiceWaveLevels.length; i++) {
            double randomValue =
                0.2 + (DateTime.now().millisecondsSinceEpoch % 600) / 800;
            double waveEffect = (i / _voiceWaveLevels.length) * 0.4;
            _voiceWaveLevels[i] = (randomValue + waveEffect).clamp(0.1, 1.0);
          }
        });
      }
    });
  }

  Future<void> _stopVoiceRecordingAndSend() async {
    if (!_isRecordingVoice) return;
    _voiceTimer?.cancel();
    _waveTimer?.cancel();
    try {
      await _voiceRecorder?.stopRecorder();
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
        _showCriticalError("التسجيل قصير جداً");
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
      final url = Uri.parse("$serverUrl/chat/upload_voice");
      http.MultipartRequest request = http.MultipartRequest('POST', url);

      final file = File(_currentVoicePath!);
      if (await file.exists()) {
        int fileLength = await file.length();
        if (fileLength == 0 || fileLength < 2000) {
          _showCriticalError("الملف الصوتي فارغ، تأكد من صلاحيات المايكروفون");
          return;
        }
        request.files.add(
          await http.MultipartFile.fromPath(
            'chat_file',
            _currentVoicePath!,
            contentType: MediaType('audio', 'aac'),
          ),
        );
      } else {
        _showCriticalError("الملف الصوتي غير موجود محلياً");
        return;
      }

      request.fields['chat_id'] = chatId!;
      request.fields['sender_id'] = widget.currentUserId;
      request.fields['duration'] = _voiceDuration.inSeconds.toString();

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        String rawFileName = responseData['url'] ??
            responseData['message']?['message'] ??
            responseData['path'] ??
            "";
        String fileName = rawFileName.contains('/')
            ? rawFileName.split('/').last
            : rawFileName;
        _deleteVoiceFile();

        var messageData = {
          "chat_id": chatId,
          "sender_id": widget.currentUserId,
          "message": fileName,
          "type": "voice",
          "duration": _voiceDuration.inSeconds,
          "created_at": DateTime.now().toIso8601String(),
          "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
        };
        socket?.emit("message", messageData);
        setState(() => _messages.insert(0, messageData));
        _autoScrollToLatest();
      } else {
        throw Exception("Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      _showCriticalError("فشل إرسال الصوت: $e");
    }
  }

  // ==================== رفع الملفات والوسائط ====================
  Future<void> _pickImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image != null) {
      if (mounted) Navigator.pop(context);
      final bytes = await image.readAsBytes();
      _showPreviewDialog(image, bytes);
    }
  }

  Future<void> _pickAndUploadDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        if (mounted) Navigator.pop(context);
        final file = result.files.first;
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        var request = http.MultipartRequest(
          'POST',
          Uri.parse("$serverUrl/chat/upload"),
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
            "chat_id": chatId,
            "sender_id": widget.currentUserId,
            "message": fileName,
          };
          setState(() {
            _messages.insert(0, {
              ...messageData,
              "created_at": DateTime.now().toIso8601String(),
              "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
            });
          });
          _autoScrollToLatest();
          socket?.emit("message", messageData);
        } else {
          _showCriticalError("خطأ في السيرفر: ${response.statusCode}");
        }
      }
    } catch (e) {
      _showCriticalError("تعذر رفع المستند.");
    }
  }

  void _showPreviewDialog(XFile xFile, Uint8List bytes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
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
        Uri.parse("$serverUrl/chat/upload"),
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
          "chat_id": chatId,
          "sender_id": widget.currentUserId,
          "message": fileName,
        };
        socket?.emit("message", messageData);
        setState(() {
          _messages.insert(0, {
            ...messageData,
            "created_at": DateTime.now().toIso8601String(),
            "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
          });
        });
        _autoScrollToLatest();
      } else {
        _showCriticalError("خطأ في السيرفر: ${response.statusCode}");
      }
    } catch (e) {
      _showCriticalError("تعذر رفع الصورة.");
    }
  }

  void _showPreviewFromCamera(Uint8List bytes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
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
        Uri.parse("$serverUrl/chat/upload"),
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
          "chat_id": chatId,
          "sender_id": widget.currentUserId,
          "message": fileName,
        };
        socket?.emit("message", messageData);
        setState(() {
          _messages.insert(0, {
            ...messageData,
            "created_at": DateTime.now().toIso8601String(),
            "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
          });
        });
        _autoScrollToLatest();
      } else {
        _showCriticalError("خطأ في السيرفر: ${response.statusCode}");
      }
    } catch (e) {
      _showCriticalError("تعذر رفع الصورة الملتقطة.");
    }
  }

  Future<void> _openMapPicker() async {
    Navigator.pop(context);
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LocationPickerPage()),
    );
    if (result != null) {
      double lat = result['lat'];
      double lng = result['lng'];
      String locationString = "LOCATION:$lat,$lng";
      var messageData = {
        "chat_id": chatId,
        "sender_id": widget.currentUserId,
        "message": locationString,
      };
      socket?.emit("message", messageData);
      setState(() {
        _messages.insert(0, {
          ...messageData,
          "created_at": DateTime.now().toIso8601String(),
          "id": "temp_${DateTime.now().millisecondsSinceEpoch}",
        });
      });
      _autoScrollToLatest();
    }
  }

  // ==================== التحديد المتعدد والإجراءات ====================
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

  void _exitSelectionMode() {
    setState(() {
      isSelectionMode = false;
      selectedMessageIds.clear();
      _selectedAction = '';
    });
  }

  void _activateSelectionMode(Map<String, dynamic> msg,
      {required String action}) {
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
        final selectedMsgs = _messages
            .where((m) => selectedMessageIds.contains(m['id'].toString()))
            .toList();
        for (var msg in selectedMsgs) {
          _executeForwardMessage(msg);
        }
        break;
      default:
        break;
    }
    _exitSelectionMode();
  }

  void _handleBulkDelete({bool forEveryone = false}) {
    for (var id in selectedMessageIds) {
      if (forEveryone) {
        final msg = _messages.firstWhere((m) => m['id'].toString() == id);
        if (msg['sender_id'] == widget.currentUserId) {
          socket?.emit("delete_message", {"message_id": id, "chat_id": chatId});
        }
      } else {
        socket?.emit("delete_for_me", {
          "message_id": id,
          "user_id": widget.currentUserId,
        });
      }
      _messages.removeWhere((m) => m['id'].toString() == id);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          forEveryone ? "تم حذف الرسائل للجميع" : "تم حذف الرسائل لديك",
        ),
      ),
    );
  }

  void _handleBulkShare() {
    final selectedMessages = _messages
        .where((msg) => selectedMessageIds.contains(msg['id'].toString()))
        .toList();
    final texts = selectedMessages.map((msg) {
      final content = msg['message'] ?? '';
      if (content.startsWith("LOCATION:")) {
        final coords = content.replaceFirst("LOCATION:", "").split(",");
        return "https://www.google.com/maps/search/?api=1&query=${coords[0]},${coords[1]}";
      }
      return content;
    }).join("\n\n");
    Share.share(texts);
  }

  void _copySingleMessage(Map<String, dynamic> msg) {
    Clipboard.setData(ClipboardData(text: msg['message'] ?? ""));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("تم نسخ النص")));
  }

  bool _areAllSelectedMessagesMine() {
    if (selectedMessageIds.isEmpty) return false;
    return _messages
        .where((m) => selectedMessageIds.contains(m['id'].toString()))
        .every((m) => m['sender_id'] == widget.currentUserId);
  }

  Future<void> _executeForwardMessage(
      Map<String, dynamic> originalMessage) async {
    final currentChatId = chatId;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPageForForward(
          currentUserId: widget.currentUserId,
          socket: socket!,
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
              if (targetChatId?.toString() == currentChatId?.toString()) {
                setState(() {
                  _messages.insert(0, {
                    ...originalMessage,
                    "created_at": DateTime.now().toIso8601String(),
                    "id": "forward_${DateTime.now().millisecondsSinceEpoch}",
                    "forwarded": true,
                  });
                });
                _autoScrollToLatest();
              }
            }
          },
        ),
      ),
    );
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
        value: 'reply',
        child: Row(
          children: [
            Icon(Icons.reply, color: Colors.blue, size: 20),
            SizedBox(width: 12),
            Text("رد"),
          ],
        ),
      ),
    );
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
        case 'reply':
          _startReplyBySwipe(msg);
          break;
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

  // ==================== دوال مساعدة عامة ====================
  bool _isImageMessage(String message) {
    final lowercaseMsg = message.toLowerCase();
    return lowercaseMsg.endsWith('.jpg') ||
        lowercaseMsg.endsWith('.jpeg') ||
        lowercaseMsg.endsWith('.png') ||
        lowercaseMsg.endsWith('.gif');
  }

  bool _isVideoMessage(String message) {
    final lowercaseMsg = message.toLowerCase();
    return lowercaseMsg.endsWith('.mp4') ||
        lowercaseMsg.endsWith('.mov') ||
        lowercaseMsg.endsWith('.avi') ||
        lowercaseMsg.endsWith('.mkv');
  }

  bool _isVoiceMessage(String message) {
    final lowercaseMsg = message.toLowerCase();
    return lowercaseMsg.contains('voice_') ||
        lowercaseMsg.endsWith('.opus') ||
        lowercaseMsg.endsWith('.m4a') ||
        lowercaseMsg.endsWith('.webm') ||
        lowercaseMsg.endsWith('.mp3') ||
        lowercaseMsg.endsWith('.wav') ||
        lowercaseMsg.endsWith('.aac');
  }

  bool _isDocumentMessage(String message) {
    final lowercaseMsg = message.toLowerCase();
    if (message.startsWith("LOCATION:")) return false;
    if (_isImageMessage(message)) return false;
    if (_isVideoMessage(message)) return false;
    if (_isVoiceMessage(message)) return false;
    return lowercaseMsg.contains('.');
  }

  String? _getFullAvatarUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return null;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    String cleanUrl = url.startsWith('/') ? url.substring(1) : url;

    if (cleanUrl.startsWith('uploads/') ||
        cleanUrl.startsWith('uploads_camera/') ||
        cleanUrl.startsWith('uploads_office/') ||
        cleanUrl.startsWith('uploads_reports/') ||
        cleanUrl.startsWith('uploads_tickets/')) {
      return '$serverUrl/$cleanUrl';
    }

    if (cleanUrl.startsWith('camera-') ||
        cleanUrl.startsWith('voice_') ||
        cleanUrl.startsWith('profile_') ||
        cleanUrl.startsWith('office_') ||
        cleanUrl.startsWith('report_') ||
        cleanUrl.startsWith('ticket_')) {
      if (cleanUrl.startsWith('camera-')) {
        return '$serverUrl/uploads_camera/$cleanUrl';
      } else if (cleanUrl.startsWith('office_')) {
        return '$serverUrl/uploads_office/$cleanUrl';
      } else if (cleanUrl.startsWith('report_')) {
        return '$serverUrl/uploads_reports/$cleanUrl';
      } else if (cleanUrl.startsWith('ticket_')) {
        return '$serverUrl/uploads_tickets/$cleanUrl';
      } else {
        return '$serverUrl/uploads/$cleanUrl';
      }
    }

    if (cleanUrl.contains('.')) {
      final ext = cleanUrl.split('.').last.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif'].contains(ext)) {
        return '$serverUrl/uploads/$cleanUrl';
      } else if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        return '$serverUrl/uploads_camera/$cleanUrl';
      } else {
        return '$serverUrl/uploads/$cleanUrl';
      }
    }

    return '$serverUrl/uploads/$cleanUrl';
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return "";
    try {
      DateTime dt = DateTime.parse(createdAt.toString()).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      return "";
    }
  }

  String _formatLastSeen(String lastSeenStr) {
    if (lastSeenStr.isEmpty) return "";
    try {
      DateTime dt = DateTime.parse(lastSeenStr).toLocal();
      return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return lastSeenStr;
    }
  }

  void _showImageOnly(String? imageUrl) {
    if (imageUrl == null) return;
    showDialog(
      context: context,
      builder: (context) => Scaffold(
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
              errorBuilder: (context, error, stackTrace) => const Center(
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

  void _showVideoFullScreen(
    String videoUrl,
    String messageId,
    bool wasPlaying,
    Duration position,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _VideoPlayerScreen(
          videoUrl: videoUrl,
          messageId: messageId,
          initialPosition: position,
          wasPlaying: wasPlaying,
        ),
      ),
    );
  }

  String _getTypeFromMessage(String message) {
    if (_isImageMessage(message)) return 'image';
    if (_isVideoMessage(message)) return 'video';
    if (_isVoiceMessage(message)) return 'voice';
    if (_isDocumentMessage(message)) return 'document';
    if (message.startsWith("LOCATION:")) return 'location';
    return 'text';
  }

  // ==================== بناء واجهة المستخدم ====================
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

  // ==================== بطاقة المكالمات ====================
  Widget _buildCallLogCard(String status, int duration, bool isMe) {
    String label;
    IconData icon;
    Color color;

    switch (status) {
      case 'accepted':
        if (isMe) {
          label = 'مكالمة صادرة';
          icon = Icons.call_made;
          color = Colors.blue.shade700;
        } else {
          label = 'مكالمة مستلمة';
          icon = Icons.call_received;
          color = Colors.green.shade700;
        }
        break;

      case 'missed':
        if (isMe) {
          label = 'مكالمة صادرة';
          icon = Icons.call_made;
          color = Colors.blue.shade700;
        } else {
          label = 'مكالمة فائتة';
          icon = Icons.call_missed;
          color = Colors.red.shade700;
        }
        break;

      case 'rejected':
        if (isMe) {
          // ✅ المتصل يرى "مكالمة ملغاة"
          label = 'مكالمة ملغاة';
          icon = Icons.call_missed;
          color = Colors.red.shade700;
        } else {
          label = 'مكالمة مرفوضة';
          icon = Icons.call_missed_outgoing;
          color = Colors.orange.shade700;
        }
        break;
      case 'cancelled':
        if (isMe) {
          label = 'مكالمة ملغاء';
          icon = Icons.call_missed;
          color = Colors.red.shade700;
        } else {
          label = 'مكالمة فائتة';
          icon = Icons.call_missed;
          color = Colors.red.shade700;
        }
        break;

      case 'busy':
        label = 'المستخدم مشغول';
        icon = Icons.phonelink_ring;
        color = Colors.deepOrange.shade700;
        break;

      default:
        label = 'مكالمة';
        icon = Icons.call;
        color = Colors.grey;
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (duration > 0)
                  Text(
                    'المدة: $duration ثانية',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallLogMessage(Map<String, dynamic> msg, bool isMe) {
    try {
      final data = jsonDecode(msg['message']);
      final String status = data['status'] ?? 'missed';
      final int duration = data['duration'] ?? 0;
      return _buildCallLogCard(status, duration, isMe);
    } catch (e) {
      String text = msg['message'] ?? 'مكالمة';
      text = text.replaceAll('📞', '').trim();
      String status = 'missed';
      if (text.contains('مستلمة'))
        status = 'accepted';
      else if (text.contains('صادرة'))
        status = 'accepted';
      else if (text.contains('فائتة'))
        status = 'missed';
      else if (text.contains('مرفوضة'))
        status = 'rejected';
      else if (text.contains('ملغاء'))
        status = 'cancelled';
      else if (text.contains('مشغول')) status = 'busy';
      return _buildCallLogCard(status, 0, isMe);
    }
  }

  // ==================== فقاعة النص ====================
  Widget _buildTextBubble(
    String text,
    bool isMe,
    String time, {
    bool isForwarded = false,
    Map<String, dynamic>? replyTo,
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
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (replyTo != null && replyTo is Map<String, dynamic>)
            Align(
              alignment: Alignment.centerRight,
              child: _buildReplyCard(replyTo, isMe),
            ),
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

  // ==================== فقاعة الصورة ====================
  Widget _buildImageWidget(
    dynamic msgData,
    bool isMe, {
    bool isForwarded = false,
    Map<String, dynamic>? replyTo,
  }) {
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
            if (replyTo != null && replyTo is Map<String, dynamic>)
              Align(
                alignment: Alignment.centerRight,
                child: _buildReplyCard(replyTo, isMe),
              ),
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

  // ==================== فقاعة الفيديو ====================
  Widget _buildVideoWidget(
    String videoUrl,
    bool isMe,
    String messageId, {
    bool isForwarded = false,
    Map<String, dynamic>? replyTo,
  }) {
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
            if (replyTo != null && replyTo is Map<String, dynamic>)
              Align(
                alignment: Alignment.centerRight,
                child: _buildReplyCard(replyTo, isMe),
              ),
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

  // ==================== فقاعة الملف ====================
  Widget _buildDocumentWidget(
    String fileName,
    bool isMe, {
    bool isForwarded = false,
    Map<String, dynamic>? replyTo,
  }) {
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
          if (replyTo != null && replyTo is Map<String, dynamic>)
            Align(
              alignment: Alignment.centerRight,
              child: _buildReplyCard(replyTo, isMe),
            ),
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

  // ==================== فقاعة الصوت ====================
  Widget _buildVoiceMessageWidget(
    String fileName,
    bool isMe,
    int duration,
    String msgId, {
    bool isForwarded = false,
    Map<String, dynamic>? replyTo,
  }) {
    final fullUrl = _getFullAvatarUrl(fileName);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeColor = isDark ? Colors.white70 : Colors.grey.shade600;
    if (fullUrl == null || fullUrl.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _getBubbleColor(isMe, context),
          borderRadius: _getBubbleBorderRadius(isMe),
        ),
        child: const Text('ملف صوتي غير متوفر'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyTo != null && replyTo is Map<String, dynamic>)
          Align(
            alignment: Alignment.centerRight,
            child: _buildReplyCard(replyTo, isMe),
          ),
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

  // ==================== فقاعة الموقع ====================
  Widget _buildLocationMessage(
    String msg,
    bool isMe,
    String msgId, {
    bool isForwarded = false,
    Map<String, dynamic>? replyTo,
  }) {
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getBubbleColor(isMe, context),
          borderRadius: _getBubbleBorderRadius(isMe),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTo != null && replyTo is Map<String, dynamic>)
              Align(
                alignment: Alignment.centerRight,
                child: _buildReplyCard(replyTo, isMe),
              ),
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

  // ==================== محتوى الرسالة الرئيسي ====================
  Widget _buildMessageContent(
    Map<String, dynamic> msg,
    bool isMe,
    String msgId,
  ) {
    final String msgContent = msg['message'] ?? "";
    final String msgType = msg['type'] ?? "";
    final int duration = msg['duration'] ?? 0;
    final String time = _formatTime(msg['created_at']);
    final bool isForwarded = msg['forwarded'] == true;
    final replyTo = msg['reply_to'];

    if (msgType == 'call_log' ||
        msgType == 'call_missed' ||
        msgType == 'call_accepted') {
      return _buildCallLogMessage(msg, isMe);
    }

    final bool isImg = _isImageMessage(msgContent);
    final bool isVideo = _isVideoMessage(msgContent);
    final bool isDoc = _isDocumentMessage(msgContent);
    final bool isLoc = msgContent.startsWith("LOCATION:");
    final bool isVoice = msgType == 'voice' || _isVoiceMessage(msgContent);

    if (replyTo == null || replyTo is! Map) {
      if (isLoc)
        return _buildLocationMessage(
          msgContent,
          isMe,
          msgId,
          isForwarded: isForwarded,
        );
      if (isImg) return _buildImageWidget(msg, isMe, isForwarded: isForwarded);
      if (isVideo)
        return _buildVideoWidget(
          msgContent,
          isMe,
          msgId,
          isForwarded: isForwarded,
        );
      if (isDoc)
        return _buildDocumentWidget(msgContent, isMe, isForwarded: isForwarded);
      if (isVoice)
        return _buildVoiceMessageWidget(
          msgContent,
          isMe,
          duration,
          msgId,
          isForwarded: isForwarded,
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
        isForwarded: isForwarded,
        replyTo: safeReplyTo,
      );
    } else if (isImg) {
      innerContent = _buildImageWidget(
        msg,
        isMe,
        isForwarded: isForwarded,
        replyTo: safeReplyTo,
      );
    } else if (isVideo) {
      innerContent = _buildVideoWidget(
        msgContent,
        isMe,
        msgId,
        isForwarded: isForwarded,
        replyTo: safeReplyTo,
      );
    } else if (isDoc) {
      innerContent = _buildDocumentWidget(
        msgContent,
        isMe,
        isForwarded: isForwarded,
        replyTo: safeReplyTo,
      );
    } else if (isVoice) {
      innerContent = _buildVoiceMessageWidget(
        msgContent,
        isMe,
        duration,
        msgId,
        isForwarded: isForwarded,
        replyTo: safeReplyTo,
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
    if (isVoice)
      exactWidth = 240;
    else if (isImg || isVideo)
      exactWidth = 250;
    else if (isDoc) exactWidth = 260;

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

  // ==================== بناء فقاعة الرسالة ====================
  Widget _buildMessageBubble(Map<String, dynamic> msg, int index) {
    final bool isMe = msg['sender_id'].toString() == widget.currentUserId;
    final String msgId = msg['id'].toString();
    final bool isSelected = selectedMessageIds.contains(msgId);

    Widget messageContentWidget = _buildMessageContent(msg, isMe, msgId);

    Widget selectionIconWidget = isSelectionMode
        ? Padding(
            padding: EdgeInsets.only(
              left: isMe ? 8 : 0,
              right: isMe ? 0 : 8,
            ),
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

    // ✅ ترتيب العناصر حسب الطلب: يمين للمرسل، يسار للمستقبل
    Widget messageRow = Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: isMe
          ? [
              // المرسل: المحتوى ثم الأيقونة (يمين)
              messageContentWidget,
              selectionIconWidget,
            ]
          : [
              // المستقبل: الأيقونة ثم المحتوى (يسار)
              selectionIconWidget,
              messageContentWidget,
            ],
    );

    if (isSelectionMode) {
      return GestureDetector(
        onTap: () => _toggleMessageSelection(msgId),
        child: messageRow,
      );
    }

    // باقي الكود للسحب للرد (نفسه)
    double _dragOffset = 0.0;
    bool _isDragging = false;

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
          onLongPress: () {
            HapticFeedback.lightImpact();
            final RenderBox? renderBox =
                context.findRenderObject() as RenderBox?;
            final Offset position =
                renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
            _showOptionsPopupMenu(context, msg, position);
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

  // ==================== شريط الإدخال ====================
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_voiceWaveLevels.length, (i) {
                    double height = 4 + (_voiceWaveLevels[i] * 24);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 60),
                      width: 3,
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: i % 2 == 0 ? Colors.grey[400] : Colors.grey[600],
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    );
                  }),
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
    final backgroundColorMain = isDark ? Colors.black87 : Colors.white;
    final textFieldBackgroundColor =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5);
    final borderColor = isDark ? Colors.grey[800] : Colors.grey[300];
    final iconColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white : Colors.black87;

    Widget _smartButton() {
      if (_showSendButton) {
        return GestureDetector(
          onTap: () {
            _sendMessage();
            setState(() => _showSendButton = false);
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
    }

    return Column(
      children: [
        _buildReplyBar(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          color: backgroundColorMain,
          child: Row(
            children: [
              if (!_isRecordingVoice)
                IconButton(
                  icon: Icon(Icons.attach_file, color: iconColor),
                  onPressed: _showAttachSheet,
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
                                controller: _controller,
                                onChanged: (v) => setState(
                                  () => _showSendButton = v.trim().isNotEmpty,
                                ),
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
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CameraScreen(
                          chatId: chatId!,
                          currentUserId: widget.currentUserId,
                          socket: socket!,
                        ),
                      ),
                    );
                    if (result != null && result is Uint8List)
                      _showPreviewFromCamera(result);
                  },
                ),
              _smartButton(),
            ],
          ),
        ),
      ],
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _iconCreation(
                  Icons.insert_drive_file,
                  Colors.indigo,
                  "المستندات",
                  _pickAndUploadDocument,
                ),
                const SizedBox(width: 40),
                _iconCreation(
                  Icons.insert_photo,
                  Colors.purple,
                  "المعرض",
                  _pickImageFromGallery,
                ),
                const SizedBox(width: 40),
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
      actions: [
        IconButton(
          icon: const Icon(Icons.phone, color: Colors.green),
          onPressed: () => _startCall(false),
        ),
        IconButton(
          icon: const Icon(Icons.videocam, color: Colors.blue),
          onPressed: () => _startCall(true),
        ),
        const SizedBox(width: 8),
      ],
      backgroundColor: isDark ? Colors.black : Colors.white,
      elevation: 0,
      leading: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.arrow_back, color: iconColor),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          GestureDetector(
            onTap: () =>
                _showImageOnly(_getFullAvatarUrl(widget.chatmodel.icon)),
            child: Hero(
              tag: "avatar_hero",
              child: CircleAvatar(
                radius: 19,
                backgroundImage: widget.chatmodel.icon.isNotEmpty
                    ? NetworkImage(_getFullAvatarUrl(widget.chatmodel.icon)!)
                    : null,
                child: widget.chatmodel.icon.isEmpty
                    ? Icon(Icons.person, color: iconColor)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.chatmodel.name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
              Text(
                isOnline ? "نشط الآن" : "غير متصل",
                style: TextStyle(
                  fontSize: 13,
                  color: iconColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== البناء الرئيسي ====================
  @override
  Widget build(BuildContext context) {
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
            child: Image.asset(
              imagePath,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
          ),
          Column(
            children: [
              Expanded(
                child: isLoading
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
                    : ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        addAutomaticKeepAlives: false,
                        cacheExtent: 500,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          return _buildMessageBubble(msg, index);
                        },
                      ),
              ),
              _buildMessageInput(),
            ],
          ),
          if (_isCalling &&
              CallManager().callService?.state == CallState.ringing)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: Card(
                    elevation: 20,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipOval(
                            child: (_callingUserImage != null &&
                                    _callingUserImage!.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: _callingUserImage!,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 100,
                                      height: 100,
                                      decoration: const BoxDecoration(
                                        color: Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.person,
                                          size: 50, color: Colors.white),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                      width: 100,
                                      height: 100,
                                      decoration: const BoxDecoration(
                                        color: Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.person,
                                          size: 50, color: Colors.white),
                                    ),
                                  )
                                : Container(
                                    width: 100,
                                    height: 100,
                                    decoration: const BoxDecoration(
                                      color: Colors.grey,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.person,
                                        size: 50, color: Colors.white),
                                  ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            _callingUserName ?? widget.chatmodel.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _callStatusText,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () async {
                              _callEndHandled = true;
                              await CallManager().callService?.endCall(
                                    reason: "إلغاء المكالمة",
                                  );
                              if (mounted) {
                                setState(() {
                                  _isCalling = false;
                                  _callStatusText = "انتهت";
                                });
                              }
                            },
                            icon:
                                const Icon(Icons.call_end, color: Colors.white),
                            label: const Text("إلغاء"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(150, 45),
                            ),
                          ),
                        ],
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

// ==================== صفحة عرض الفيديو بملء الشاشة ====================
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
