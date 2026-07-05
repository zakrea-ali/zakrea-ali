import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;

// ============================================================
// حالات المكالمة
// ============================================================
enum CallState {
  idle,
  ringing,
  connecting,
  connected,
  ended,
  reconnecting,
}

// ============================================================
// CallService (المعدل بالكامل مع الإصلاحات الجازمة)
// ============================================================
class CallService {
  // ---------- الأساسيات ----------
  final IO.Socket socket;
  webrtc.RTCPeerConnection? peerConnection;
  webrtc.MediaStream? localStream;
  webrtc.MediaStream? remoteStream;
  CallState state = CallState.idle;
  String? _currentCallId;
  String? targetUserId;
  bool isVideoCall = false;
  bool _isCaller = false;
  String? chatId;
  String? currentUserId;

  String callerName = '';
  String? callerAvatar;

  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isRingtonePlaying = false;

  // ---------- التحكم في الصوت والفيديو ----------
  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isCameraOn = true;
  bool get isCameraOn => _isCameraOn;

  // ---------- Getter لـ callId ----------
  String? get callId => _currentCallId;

  // 🔥 Getter لمعرفة ما إذا كان المستخدم هو المتصل
  bool get isCaller => _isCaller;

  // ---------- إعادة المحاولة والمؤقتات ----------
  Timer? _ringingTimer;
  Timer? _connectionTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 3;
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const Duration ringingTimeout = Duration(seconds: 30);
  static const Duration connectionTimeout = Duration(seconds: 15);

  // ---------- دوال الاستدعاء ----------
  Function(CallState)? onStateChanged;
  Function(webrtc.MediaStream)? onRemoteStreamAdded;
  Function(String)? onError;
  Function(String)? onCallEnded;

  // 🔒 حماية ضد التنفيذ المتكرر لـ endCall
  bool _isEnding = false;

  CallService(this.socket);

  // ============================================================
  // 1.  خوادم ICE
  // ============================================================
  List<Map<String, dynamic>> _getIceServers() {
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ];
  }

  // ============================================================
  // 2.  تهيئة PeerConnection
  // ============================================================
  Future<bool> initPeerConnection(bool video) async {
    isVideoCall = video;
    try {
      peerConnection = await webrtc.createPeerConnection({
        'iceServers': _getIceServers(),
        'sdpSemantics': 'unified-plan',
      });
    } catch (e) {
      _logError('إنشاء PeerConnection', e);
      onError?.call('فشل إنشاء اتصال الوسائط');
      return false;
    }

    peerConnection!.onIceConnectionState =
        (webrtc.RTCIceConnectionState iceState) {
      _log('حالة ICE: $iceState');
      if (iceState ==
              webrtc.RTCIceConnectionState.RTCIceConnectionStateFailed ||
          iceState ==
              webrtc.RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _attemptReconnect();
      } else if (iceState ==
          webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected) {
        _reconnectAttempts = 0;
        if (state == CallState.connecting) {
          state = CallState.connected;
          onStateChanged?.call(state);
        }
      }
    };

    peerConnection!.onIceGatheringState =
        (webrtc.RTCIceGatheringState gatherState) {
      if (gatherState ==
          webrtc.RTCIceGatheringState.RTCIceGatheringStateComplete) {
        socket.emit('ice_gathering_complete', {
          'to': targetUserId,
          'call_id': _currentCallId,
        });
      }
    };

    peerConnection!.onIceCandidate = (webrtc.RTCIceCandidate? candidate) {
      if (candidate != null && _currentCallId != null && targetUserId != null) {
        socket.emit('ice_candidate', {
          'to': targetUserId,
          'call_id': _currentCallId,
          'candidate': candidate.toMap(),
        });
      }
    };

    peerConnection!.onTrack = (webrtc.RTCTrackEvent event) {
      if (event.track.kind == 'video' || event.track.kind == 'audio') {
        remoteStream = event.streams[0];
        onRemoteStreamAdded?.call(remoteStream!);
      }
    };

    return true;
  }

  // ============================================================
  // 3.  الحصول على الدفق المحلي
  // ============================================================
  Future<void> startLocalStream(bool video) async {
    Map<String, dynamic> mediaConstraints;
    if (kIsWeb) {
      mediaConstraints = {
        'audio': true,
        'video': video
            ? {
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 30},
              }
            : false,
      };
    } else {
      mediaConstraints = {
        'audio': true,
        'video': video
            ? {
                'mandatory': {'minWidth': '640', 'minHeight': '480'},
                'facingMode': 'user',
              }
            : false,
      };
    }
    try {
      localStream =
          await webrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
      if (video && localStream!.getVideoTracks().isEmpty) {
        throw Exception('لم يتم الحصول على كاميرا');
      }
      _isCameraOn = video;
    } catch (e) {
      _logError('الحصول على الوسائط', e);
      onError?.call('تعذر الوصول إلى الكاميرا أو الميكروفون');
      rethrow;
    }
  }

  // ============================================================
  // 4.  بدء مكالمة (المتصل)
  // ============================================================
  Future<void> makeCall(
    String userId,
    bool video, {
    String name = '',
    String? avatar,
    String? myName,
    String? myAvatar,
  }) async {
    _isCaller = true;
    targetUserId = userId;
    isVideoCall = video;
    _currentCallId = DateTime.now().millisecondsSinceEpoch.toString();

    callerName = name;
    callerAvatar = avatar;

    await startLocalStream(video);
    bool initSuccess = await initPeerConnection(video);
    if (!initSuccess) return;

    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        await peerConnection?.addTrack(track, localStream!);
      }
    }

    final webrtc.RTCSessionDescription offer =
        await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    socket.emit('call_offer', {
      'to': userId,
      'chat_id': chatId,
      'call_id': _currentCallId,
      'video': video,
      'offer': offer.sdp,
      'caller_name': myName ?? '',
      'caller_avatar': myAvatar,
    });
    await Future.delayed(const Duration(milliseconds: 600));
    await _playRingtone();
    state = CallState.ringing;
    onStateChanged?.call(state);
    _startRingingTimer();
  }

  // ============================================================
  // 5.  قبول مكالمة (المستقبل)
  // ============================================================
  Future<void> acceptCall(
    String fromUserId,
    String callId,
    bool video,
    String offerSdp, {
    String name = '',
    String? avatar,
  }) async {
    _isCaller = false;
    targetUserId = fromUserId;
    _currentCallId = callId;
    isVideoCall = video;
    callerName = name;
    callerAvatar = avatar;

    await startLocalStream(video);
    bool initSuccess = await initPeerConnection(video);
    if (!initSuccess) return;

    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        await peerConnection?.addTrack(track, localStream!);
      }
    }

    await peerConnection!.setRemoteDescription(
      webrtc.RTCSessionDescription(offerSdp, 'offer'),
    );

    final webrtc.RTCSessionDescription answer =
        await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);

    socket.emit('call_answer', {
      'to': fromUserId,
      'call_id': callId,
      'answer': answer.sdp,
    });

    await _stopRingtone();
    await _playConnectedSound();
    state = CallState.connected;
    onStateChanged?.call(state);
    _applyAudioRoute();
  }

  // ============================================================
  // 6.  معالجة الرد
  // ============================================================
  Future<void> handleAnswer(String answerSdp) async {
    if (peerConnection == null) return;
    try {
      await peerConnection!.setRemoteDescription(
        webrtc.RTCSessionDescription(answerSdp, 'answer'),
      );
      await _stopRingtone();
      await _playConnectedSound();
      state = CallState.connected;
      onStateChanged?.call(state);
      _applyAudioRoute();
      _cancelTimers();
    } catch (e) {
      _logError('معالجة الرد', e);
      onError?.call('فشل إنشاء الاتصال');
      state = CallState.ended;
      onStateChanged?.call(state);
    }
  }

  // ============================================================
  // 7.  معالجة مرشح ICE
  // ============================================================
  Future<void> handleIceCandidate(dynamic candidateData) async {
    if (peerConnection == null) return;
    try {
      Map<String, dynamic> candidateMap;
      if (candidateData is Map) {
        candidateMap = Map<String, dynamic>.from(candidateData);
      } else if (candidateData is String) {
        candidateMap = jsonDecode(candidateData);
      } else {
        candidateMap = jsonDecode(jsonEncode(candidateData));
      }
      final candidate = webrtc.RTCIceCandidate(
        candidateMap['candidate'] ?? '',
        candidateMap['sdpMid'] ?? '',
        candidateMap['sdpMLineIndex'] ?? 0,
      );
      await peerConnection!.addCandidate(candidate);
    } catch (e) {
      _logError('إضافة مرشح ICE', e);
    }
  }

  // ============================================================
  // 8.  إعادة محاولة ICE
  // ============================================================
  Future<void> _attemptReconnect() async {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _log('انتهت محاولات إعادة الاتصال');
      endCall(reason: 'تعذر إعادة الاتصال');
      return;
    }
    if (state == CallState.ended) return;

    _reconnectAttempts++;
    _log('محاولة إعادة الاتصال $_reconnectAttempts/$maxReconnectAttempts');
    state = CallState.reconnecting;
    onStateChanged?.call(state);

    try {
      await Future.delayed(reconnectDelay);
      if (peerConnection != null) {
        if (_isCaller) {
          final offer = await peerConnection!.createOffer();
          await peerConnection!.setLocalDescription(offer);
          socket.emit('call_offer', {
            'to': targetUserId,
            'call_id': _currentCallId,
            'video': isVideoCall,
            'offer': offer.sdp,
            'caller_name': callerName,
            'caller_avatar': callerAvatar,
          });
        } else {
          final answer = await peerConnection!.createAnswer();
          await peerConnection!.setLocalDescription(answer);
          socket.emit('call_answer', {
            'to': targetUserId,
            'call_id': _currentCallId,
            'answer': answer.sdp,
          });
        }
        _startConnectionTimer();
      }
    } catch (e) {
      _logError('فشلت محاولة إعادة الاتصال', e);
      _attemptReconnect();
    }
  }

  // ============================================================
  // 9.  مؤقتات المهلة
  // ============================================================
  void _startRingingTimer() {
    _ringingTimer?.cancel();
    _ringingTimer = Timer(ringingTimeout, () {
      if (state == CallState.ringing) {
        _log('انتهت مهلة الرنين');
        endCall(reason: 'لم يجب المستخدم');
      }
    });
  }

  void _startConnectionTimer() {
    _connectionTimer?.cancel();
    _connectionTimer = Timer(connectionTimeout, () {
      if (state == CallState.connecting || state == CallState.reconnecting) {
        _log('انتهت مهلة الاتصال');
        _attemptReconnect();
      }
    });
  }

  void _cancelTimers() {
    _ringingTimer?.cancel();
    _connectionTimer?.cancel();
  }

  // ============================================================
  // 10. التحكم في الصوت والفيديو
  // ============================================================
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    _applyAudioRoute();
    _log('مكبر الصوت: ${_isSpeakerOn ? "ON" : "OFF"}');
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    if (localStream != null) {
      for (var track in localStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
    _log('كتم الصوت: ${_isMuted ? "ON" : "OFF"}');
  }

  Future<void> toggleCamera() async {
    if (!isVideoCall) return;
    _isCameraOn = !_isCameraOn;
    if (localStream != null) {
      for (var track in localStream!.getVideoTracks()) {
        track.enabled = _isCameraOn;
      }
    }
    _log('الكاميرا: ${_isCameraOn ? "ON" : "OFF"}');
  }

  Future<void> switchCamera() async {
    if (!isVideoCall) return;
    await localStream?.dispose();
    try {
      localStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'mandatory': {'minWidth': '640', 'minHeight': '480'},
          'facingMode': 'environment',
        },
      });
      if (localStream != null) {
        for (var track in localStream!.getTracks()) {
          await peerConnection?.addTrack(track, localStream!);
        }
      }
      _log('تم تبديل الكاميرا');
    } catch (e) {
      _logError('تبديل الكاميرا', e);
      onError?.call('فشل تبديل الكاميرا');
    }
  }

  // ============================================================
  // 11. تطبيق مسار الصوت (Speaker / Earpiece)
  // ============================================================
  void _applyAudioRoute() {
    if (!kIsWeb) {
      try {
        Helper.setSpeakerphoneOn(_isSpeakerOn);
      } catch (e) {
        _logError('تطبيق مسار الصوت', e);
      }
    }

    if (_isRingtonePlaying) {
      _ringtonePlayer.setVolume(_isSpeakerOn ? 1.0 : 0.3);
    }
  }

  // ============================================================
  // 12. نغمات الرنين والاتصال
  // ============================================================
  Future<void> _playRingtone() async {
    if (_isRingtonePlaying) return;
    try {
      _applyAudioRoute();
      await _ringtonePlayer.stop();
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(_isSpeakerOn ? 1.0 : 0.3);
      await _ringtonePlayer.play(AssetSource('sounds/ringtone.mp3'));
      _isRingtonePlaying = true;
      _log('تشغيل نغمة الرنين');
    } catch (e) {
      _logError('تشغيل نغمة الرنين', e);
    }
  }

  Future<void> _stopRingtone() async {
    if (!_isRingtonePlaying) return;
    await _ringtonePlayer.stop();
    _isRingtonePlaying = false;
    _log('إيقاف نغمة الرنين');
  }

  Future<void> _playConnectedSound() async {
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/call_connected.mp3'));
      await Future.delayed(const Duration(seconds: 1));
      await player.dispose();
    } catch (e) {
      // تجاهل
    }
  }

  // ============================================================
  // 13. إنهاء المكالمة - النسخة المعدلة جازماً (مع منع التكرار)
  // ============================================================
  Future<void> endCall({String reason = 'انتهت المكالمة'}) async {
    // 🔒 منع التنفيذ المتكرر
    if (_isEnding) {
      _log('⛔ endCall() قيد التنفيذ بالفعل، تم تجاهل الطلب.');
      return;
    }

    _isEnding = true;
    final CallState previousState = state;
    _log('📱 استدعاء endCall. الحالة الحالية: $previousState، السبب: $reason');

    // ✅ تنظيف الموارد (دائماً)
    _cancelTimers();
    await _stopRingtone();

    if (!kIsWeb) {
      try {
        Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    }

    // تنظيف مسارات البث (دائماً)
    if (localStream != null) {
      try {
        localStream!.getTracks().forEach((track) => track.stop());
        await localStream!.dispose();
      } catch (e) {
        _logError('خطأ أثناء إغلاق localStream', e);
      }
      localStream = null;
    }

    if (remoteStream != null) {
      try {
        remoteStream!.getTracks().forEach((track) => track.stop());
        await remoteStream!.dispose();
      } catch (_) {}
      remoteStream = null;
    }

    // ⚠️ إذا كانت الحالة منتهية أو خاملة، ننظف الموارد ونخطر المستمعين فقط (لا نغلق الشاشة)
    if (previousState == CallState.ended || previousState == CallState.idle) {
      _log(
          '⚠️ المكالمة منتهية بالفعل (ended/idle)، ننظف الموارد ونخطر المستمعين.');
      onStateChanged?.call(CallState.idle);
      _isEnding = false;
      return;
    }

    // ------------------------------------------------------------
    // هنا نتعامل مع المكالمة النشطة (ليست منتهية)
    // ------------------------------------------------------------

    // تحديد الحالة (status)
    if (_currentCallId != null &&
        targetUserId != null &&
        chatId != null &&
        currentUserId != null) {
      String status;

      bool wasAnswered = (previousState == CallState.connected);

      if (wasAnswered ||
          reason == 'انتهت المكالمة' ||
          reason == 'ended' ||
          reason == 'تحدث وانتهى') {
        status = 'accepted';
      } else {
        if (reason == 'إلغاء المكالمة' || reason == 'cancelled') {
          status = 'cancelled';
        } else if (reason == 'رفض المستخدم' || reason == 'rejected') {
          status = 'rejected';
        } else if (reason == 'المستخدم مشغول' || reason == 'busy') {
          status = 'busy';
        } else {
          status = 'missed';
        }
      }

      final String callerId = _isCaller ? currentUserId! : targetUserId!;
      final String receiverId = _isCaller ? targetUserId! : currentUserId!;

      _log('📤 إرسال حدث end_call إلى السيرفر: status=$status');
      socket.emit('end_call', {
        'callId': _currentCallId!,
        'callerId': callerId,
        'receiverId': receiverId,
        'chatId': chatId!,
        'status': status,
        'duration': 0,
      });
    }

    // تغيير الحالة وإعلام المستمعين
    state = CallState.ended;
    onStateChanged?.call(state);
    state = CallState.idle;
    onStateChanged?.call(state);

    // إعادة تعيين المتغيرات
    _currentCallId = null;
    targetUserId = null;
    chatId = null;
    _isCaller = false;
    _reconnectAttempts = 0;
    callerName = '';
    callerAvatar = null;
    _isRingtonePlaying = false;
    _isSpeakerOn = false;
    _isMuted = false;
    _isCameraOn = true;

    // إعلام الواجهة بالإنهاء (لإغلاق CallScreen إذا كانت مفتوحة)
    onCallEnded?.call(reason);

    _isEnding = false;
  }

  // ============================================================
  // 14. تسجيل الأحداث
  // ============================================================
  void _log(String message) => print('📱 [CallService] $message');
  void _logError(String context, dynamic error) =>
      print('❌ [CallService] $context: $error');

  // ============================================================
  // 15. تنظيف الموارد
  // ============================================================
  void dispose() {
    _cancelTimers();
    _ringtonePlayer.dispose();
    endCall(reason: 'إغلاق الخدمة');
    socket.off('call_offer');
    socket.off('call_answer');
    socket.off('ice_candidate');
    socket.off('call_end');
    socket.off('call_reject');
    socket.off('call_busy');
    socket.off('call_error');
  }
}

// ============================================================
// CallManager (المعدل مع الإصلاحات الجازمة + منع تكرار call_end + إضافة المستمع فوراً)
// ============================================================
class CallManager {
  static final CallManager _instance = CallManager._internal();
  factory CallManager() => _instance;
  CallManager._internal();

  IO.Socket? _socket;
  CallService? _callService;
  bool _isInitialized = false;
  String? _currentUserId;

  String? _incomingCallId;
  String? _incomingCallerId;
  bool _incomingIsVideo = false;
  String? _incomingOfferSdp;
  String? _incomingCallerName;
  String? _incomingCallerAvatar;

  Function(Map<String, dynamic>)? onIncomingCall;
  Function(CallService)? onCallStarted;
  Function(String)? onCallError;

  final List<Function(CallState)> _stateListeners = [];

  // 🔒 منع معالجة نفس call_end أكثر من مرة
  bool _isCallEndProcessed = false;

  bool get isInCall =>
      _callService?.state != CallState.idle &&
      _callService?.state != CallState.ended;
  bool get isInitialized => _isInitialized;
  CallService? get callService => _callService;

  void initialize(IO.Socket socket, String userId) {
    if (_isInitialized) return;
    _socket = socket;
    _currentUserId = userId;

    // 🔑 إرسال signin إلى السيرفر
    _socket?.emit('signin', userId);
    _log('✅ تم إرسال signin للمستخدم $userId');

    _callService = CallService(socket);
    _callService!.currentUserId = userId;

    // ✅ إضافة المستمع فوراً لضمان استقبال تغييرات الحالة (حتى للمكالمات الواردة غير المقبولة)
    _addStateListener(_callService!);

    _setupCallListeners();
    _setupSocketReconnection();
    _isInitialized = true;
    _log('تم التهيئة للمستخدم $userId');
  }

  Future<void> startCall(
    String targetUserId,
    bool video,
    String chatId, {
    String name = '',
    String? avatar,
    String? myName,
    String? myAvatar,
  }) async {
    if (_callService == null || isInCall) return;

    // إعادة تعيين حماية التكرار عند بدء مكالمة جديدة
    _isCallEndProcessed = false;

    _callService!.chatId = chatId;
    _addStateListener(_callService!);

    await _callService!.makeCall(
      targetUserId,
      video,
      name: name,
      avatar: avatar,
      myName: myName,
      myAvatar: myAvatar,
    );
    onCallStarted?.call(_callService!);
  }

  Future<void> acceptCall() async {
    if (_incomingCallId == null || _incomingCallerId == null) {
      _log('لا توجد مكالمة واردة للقبول');
      return;
    }
    if (_callService == null) return;

    // إعادة تعيين حماية التكرار عند القبول
    _isCallEndProcessed = false;

    _log('جاري قبول المكالمة وتجهيز البنية التحتية...');
    _addStateListener(_callService!);

    await _callService!.acceptCall(
      _incomingCallerId!,
      _incomingCallId!,
      _incomingIsVideo,
      _incomingOfferSdp!,
      name: _incomingCallerName ?? '',
      avatar: _incomingCallerAvatar,
    );

    onCallStarted?.call(_callService!);
    _clearIncoming();
  }

  void rejectCall() {
    if (_incomingCallId != null && _incomingCallerId != null) {
      _log('📤 إرسال call_reject إلى ${_incomingCallerId}');
      _socket?.emit('call_reject', {
        'to': _incomingCallerId,
        'call_id': _incomingCallId,
        'from': _currentUserId,
      });
      if (_callService != null) {
        _callService!.endCall(reason: 'رفض المكالمة');
      } else {
        _log('⚠️ _callService غير موجود، لن يتم إنهاء المكالمة');
      }
    } else {
      _log('⚠️ لا توجد مكالمة واردة للرفض');
    }
    _clearIncoming();
  }

  void addStateListener(Function(CallState) listener) {
    if (!_stateListeners.contains(listener)) {
      _stateListeners.add(listener);
    }
  }

  void removeStateListener(Function(CallState) listener) {
    _stateListeners.remove(listener);
  }

  void _addStateListener(CallService service) {
    service.onStateChanged = (state) {
      for (var listener in _stateListeners) {
        listener(state);
      }
      if (state == CallState.ended || state == CallState.idle) {
        _clearIncoming();
        _isCallEndProcessed = false;
      }
    };
    service.onError = (error) => onCallError?.call(error);
  }

  void _setupCallListeners() {
    if (_socket == null) return;

    _socket!.off('call_offer');
    _socket!.off('call_answer');
    _socket!.off('ice_candidate');
    _socket!.off('call_end');
    _socket!.off('call_reject');
    _socket!.off('call_busy');
    _socket!.off('call_error');

    _socket!.on('call_offer', (data) {
      _log('📞 استقبال call_offer من: ${data['from']}');

      if (data['chat_id'] != null && _callService != null) {
        _callService!.chatId = data['chat_id'].toString();
        _log('🆔 تم ربط الـ chatId بالمكالمة الواردة: ${data['chat_id']}');
      }

      if (isInCall) {
        _socket?.emit('call_busy', {
          'to': data['from'],
          'call_id': data['call_id'],
        });
        return;
      }

      _incomingCallId = data['call_id'];
      _incomingCallerId = data['from'];
      _incomingIsVideo = data['video'] ?? false;
      _incomingOfferSdp = data['offer'];
      _incomingCallerName = data['caller_name'] ?? 'مستخدم';
      _incomingCallerAvatar = data['caller_avatar'];

      _log('📸 callerAvatar: $_incomingCallerAvatar');

      onIncomingCall?.call({
        'callerId': _incomingCallerId,
        'callId': _incomingCallId,
        'isVideo': _incomingIsVideo,
        'offer': _incomingOfferSdp,
        'callerName': _incomingCallerName,
        'callerAvatar': _incomingCallerAvatar,
      });
    });

    _socket!.on('call_answer', (data) async {
      await _callService?.handleAnswer(data['answer']);
    });

    _socket!.on('ice_candidate', (data) {
      _callService?.handleIceCandidate(data['candidate']);
    });

    // 🔥 مستمع call_end مع حماية من التكرار
    _socket!.on('call_end', (data) {
      _log('📥 استقبلت call_end من السيرفر: $data');

      if (_isCallEndProcessed) {
        _log('⛔ تم معالجة هذا call_end مسبقاً، تجاهل.');
        return;
      }

      if (_callService != null) {
        _isCallEndProcessed = true;
        _log('✅ callService موجود، سيتم استدعاء endCall()');
        _callService!.endCall(reason: 'انتهت من الطرف الآخر');
        _clearIncoming();
      } else {
        _log('❌ callService غير موجود، لن يتم إنهاء المكالمة');
        if (_socket != null && _currentUserId != null) {
          _log('⚠️ محاولة إعادة تهيئة CallService');
          _callService = CallService(_socket!);
          _callService!.currentUserId = _currentUserId;
          _addStateListener(_callService!);
          _callService!.endCall(reason: 'انتهت من الطرف الآخر');
          _clearIncoming();
        }
      }
    });

    _socket!.on('call_reject', (data) {
      _log('📞 استقبال call_reject من: ${data['from']}');
      if (_callService != null) {
        _callService!.endCall(reason: 'رفض المستخدم');
      }
      _clearIncoming();
    });

    _socket!.on('call_busy', (data) {
      _callService?.endCall(reason: 'المستخدم مشغول');
      _clearIncoming();
    });

    _socket!.on('call_error', (data) {
      _callService?.endCall(reason: data['message'] ?? 'خطأ');
      _clearIncoming();
    });
  }

  void _setupSocketReconnection() {
    if (_socket == null) return;
    _socket!.on('disconnect', (_) {
      _log('Socket منقطع، محاولة إعادة الاتصال...');
      _socket?.connect();
    });
    _socket!.on('reconnect', (_) {
      _log('Socket أعيد اتصاله');
      if (_currentUserId != null) {
        _socket?.emit('signin', _currentUserId);
        _log('✅ تم إعادة إرسال signin للمستخدم $_currentUserId');
      }
      if (_callService?.state == CallState.connecting ||
          _callService?.state == CallState.connected) {
        _callService?._attemptReconnect();
      }
    });
  }

  void _clearIncoming() {
    _incomingCallId = null;
    _incomingCallerId = null;
    _incomingOfferSdp = null;
    _incomingIsVideo = false;
    _incomingCallerName = null;
    _incomingCallerAvatar = null;
  }

  void _log(String message) => print('📱 [CallManager] $message');

  void dispose() {
    _stateListeners.clear();
    onIncomingCall = null;
    onCallStarted = null;
    onCallError = null;

    _callService?.dispose();
    _callService = null;

    if (_socket != null) {
      _socket!.off('call_offer');
      _socket!.off('call_answer');
      _socket!.off('ice_candidate');
      _socket!.off('call_end');
      _socket!.off('call_reject');
      _socket!.off('call_busy');
      _socket!.off('call_error');
      _socket!.off('disconnect');
      _socket!.off('reconnect');
    }

    _isInitialized = false;
    _currentUserId = null;
    _clearIncoming();
    _log('تم تنظيف وإغلاق CallManager بالكامل.');
  }
}
