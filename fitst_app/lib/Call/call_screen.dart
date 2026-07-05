import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:fitst_app/Call/call_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitst_app/main.dart';

class CallScreen extends StatefulWidget {
  final CallService callService;
  final String callerName;
  final String? callerAvatar;
  final String? serverUrl;

  const CallScreen({
    Key? key,
    required this.callService,
    required this.callerName,
    this.callerAvatar,
    this.serverUrl,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  Timer? _callDurationTimer;
  Duration _callDuration = Duration.zero;
  bool _isDisposed = false;
  bool _isClosing = false; // 🔒 منع تكرار pop

  String? _getFullImageUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return null;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final baseUrl = widget.serverUrl ?? ApiConfig.baseUrl;
    String cleanUrl = url.startsWith('/') ? url.substring(1) : url;
    if (cleanUrl.startsWith('uploads/') ||
        cleanUrl.startsWith('uploads_camera/') ||
        cleanUrl.startsWith('uploads_office/') ||
        cleanUrl.startsWith('uploads_reports/') ||
        cleanUrl.startsWith('uploads_tickets/')) {
      return '$baseUrl/$cleanUrl';
    }
    if (cleanUrl.startsWith('camera-') ||
        cleanUrl.startsWith('voice_') ||
        cleanUrl.startsWith('profile_') ||
        cleanUrl.startsWith('office_') ||
        cleanUrl.startsWith('report_') ||
        cleanUrl.startsWith('ticket_')) {
      if (cleanUrl.startsWith('camera-')) {
        return '$baseUrl/uploads_camera/$cleanUrl';
      } else if (cleanUrl.startsWith('office_')) {
        return '$baseUrl/uploads_office/$cleanUrl';
      } else if (cleanUrl.startsWith('report_')) {
        return '$baseUrl/uploads_reports/$cleanUrl';
      } else if (cleanUrl.startsWith('ticket_')) {
        return '$baseUrl/uploads_tickets/$cleanUrl';
      } else {
        return '$baseUrl/uploads/$cleanUrl';
      }
    }
    return '$baseUrl/uploads/$cleanUrl';
  }

  @override
  void initState() {
    super.initState();
    CallManager().addStateListener(_handleCallStateChanged);
    _initRenderers();

    widget.callService.onRemoteStreamAdded = (stream) {
      if (!_isDisposed && mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      }
    };
    _startCallDurationTimer();
  }

  void _handleCallStateChanged(CallState state) {
    if (_isDisposed || !mounted) return;
    setState(() {});
    if ((state == CallState.ended || state == CallState.idle) && !_isClosing) {
      _isClosing = true;
      _callDurationTimer?.cancel();
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    }
  }

  void _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (widget.callService.localStream != null) {
      _localRenderer.srcObject = widget.callService.localStream;
    }
    if (!_isDisposed && mounted) setState(() {});
  }

  void _startCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || !mounted) {
        timer.cancel();
        return;
      }
      if (widget.callService.state == CallState.connected) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
      } else if (widget.callService.state == CallState.ended) {
        timer.cancel();
      }
    });
  }

  void _toggleMute() {
    _isMuted = !_isMuted;
    widget.callService.toggleMute();
    if (mounted) setState(() {});
  }

  void _toggleSpeaker() {
    widget.callService.toggleSpeaker();
    if (mounted) setState(() {});
  }

  void _endCall() async {
    _callDurationTimer?.cancel();
    String calculatedReason = 'ended';
    if (widget.callService.state == CallState.ringing) {
      calculatedReason =
          widget.callService.callId != null ? 'rejected' : 'cancelled';
    } else if (widget.callService.state == CallState.connecting) {
      calculatedReason = 'cancelled';
    }
    await widget.callService.endCall(reason: calculatedReason);
  }

  String _formatDuration(Duration d) {
    return "${d.inMinutes.toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _isDisposed = true;
    _callDurationTimer?.cancel();
    CallManager().removeStateListener(_handleCallStateChanged);
    widget.callService.onRemoteStreamAdded = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fullImageUrl = _getFullImageUrl(widget.callerAvatar);

    return WillPopScope(
      onWillPop: () async {
        return widget.callService.state == CallState.ended ||
            widget.callService.state == CallState.idle;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // الفيديو البعيد
            Positioned.fill(
              child: widget.callService.isVideoCall
                  ? RTCVideoView(
                      _remoteRenderer,
                      mirror: false,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipOval(
                              child: fullImageUrl != null &&
                                      fullImageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: fullImageUrl,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[800],
                                        child: const Icon(Icons.person,
                                            size: 60, color: Colors.white),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        width: 120,
                                        height: 120,
                                        color: Colors.grey[800],
                                        child: const Icon(Icons.person,
                                            size: 60, color: Colors.white),
                                      ),
                                    )
                                  : Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[800],
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.person,
                                          size: 60, color: Colors.white),
                                    ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.callerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.callService.state == CallState.ringing
                                  ? "رنين..."
                                  : (widget.callService.state ==
                                          CallState.connecting
                                      ? "جاري التوصيل..."
                                      : (widget.callService.state ==
                                              CallState.connected
                                          ? ""
                                          : "انتهت")),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            // الفيديو المحلي
            if (widget.callService.isVideoCall)
              Positioned(
                top: 60,
                right: 16,
                child: Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: RTCVideoView(_localRenderer, mirror: true),
                ),
              ),
            // الأزرار السفلية
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  if (widget.callService.state == CallState.connected)
                    Text(
                      _formatDuration(_callDuration),
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        _isMuted ? Colors.red : Colors.white,
                        _toggleMute,
                      ),
                      _buildControlButton(
                        widget.callService.isSpeakerOn
                            ? Icons.volume_up
                            : Icons.volume_down,
                        widget.callService.isSpeakerOn
                            ? Colors.green
                            : Colors.white,
                        _toggleSpeaker,
                      ),
                      _buildControlButton(
                        Icons.call_end,
                        Colors.white,
                        _endCall,
                        isEnd: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(
    IconData icon,
    Color iconColor,
    VoidCallback onTap, {
    bool isEnd = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isEnd ? Colors.red : Colors.grey[800],
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: 30,
        ),
      ),
    );
  }
}
