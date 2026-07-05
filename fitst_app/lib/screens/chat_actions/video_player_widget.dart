import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// ✅ كلاس عالمي للتحكم بجميع الفيديوهات (تشغيل فيديو واحد فقط)
class VideoPlayerManager {
  static final VideoPlayerManager _instance = VideoPlayerManager._internal();
  factory VideoPlayerManager() => _instance;
  VideoPlayerManager._internal();

  VideoPlayerController? _currentController;
  String? _currentVideoId;

  void playVideo(VideoPlayerController controller, String videoId) {
    // إيقاف الفيديو الحالي إذا كان موجوداً ومختلف عن الفيديو الجديد
    if (_currentController != null && _currentController != controller) {
      _currentController!.pause();
    }
    // تشغيل الفيديو الجديد
    _currentController = controller;
    _currentVideoId = videoId;
    controller.play();
  }

  void pauseVideo() {
    _currentController?.pause();
  }

  void stopAllVideos() {
    if (_currentController != null) {
      _currentController!.pause();
      _currentController = null;
      _currentVideoId = null;
    }
  }

  void disposeController(String videoId) {
    if (_currentVideoId == videoId) {
      _currentController = null;
      _currentVideoId = null;
    }
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  final bool isMe;
  final String videoId; // ✅ معرف فريد لكل فيديو (مطلوب)
  final Function(bool isPlaying)? onPlayStateChanged;

  const VideoPlayerWidget({
    super.key,
    required this.url,
    this.isMe = false,
    required this.videoId, // ✅ مطلوب الآن
    this.onPlayStateChanged,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _showControls = true;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));

      await _controller.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _totalDuration = _controller.value.duration;
      });

      _controller.addListener(_updateProgress);

      // لا تشغيل تلقائي
      _isPlaying = false;

      widget.onPlayStateChanged?.call(false);
    } catch (e) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  void _updateProgress() {
    if (!mounted) return;

    setState(() {
      _currentPosition = _controller.value.position;
      _isPlaying = _controller.value.isPlaying;

      if (_currentPosition >= _totalDuration &&
          _totalDuration > Duration.zero) {
        _isPlaying = false;
        _showControls = true;
        widget.onPlayStateChanged?.call(false);
        // ✅ إزالة من المدير عند الانتهاء
        VideoPlayerManager().disposeController(widget.videoId);
      }
    });
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      // إيقاف الفيديو الحالي
      await _controller.pause();
      setState(() => _isPlaying = false);
      VideoPlayerManager().pauseVideo();
      widget.onPlayStateChanged?.call(false);
    } else {
      // ✅ تشغيل الفيديو الجديد وإيقاف البقية
      if (_currentPosition >= _totalDuration) {
        await _controller.seekTo(Duration.zero);
      }

      // استخدام المدير لإيقاف أي فيديو آخر وتشغيل هذا الفيديو
      VideoPlayerManager().playVideo(_controller, widget.videoId);

      setState(() => _isPlaying = true);
      widget.onPlayStateChanged?.call(true);
    }
    _showControlsTemporarily();
  }

  void _restartVideo() async {
    await _controller.seekTo(Duration.zero);
    if (!_isPlaying) {
      // ✅ تشغيل هذا الفيديو وإيقاف البقية
      VideoPlayerManager().playVideo(_controller, widget.videoId);
      setState(() => _isPlaying = true);
    }
    setState(() {
      _currentPosition = Duration.zero;
      _showControls = true;
    });
    _showControlsTemporarily();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _controller.setVolume(_isMuted ? 0 : 1);
    });
    _showControlsTemporarily();
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _openFullScreen() {
    // ✅ حفظ حالة التشغيل الحالية
    final wasPlaying = _isPlaying;
    final currentPosition = _currentPosition;

    // ✅ إيقاف الفيديو مؤقتاً قبل فتح الشاشة الكاملة
    if (_isPlaying) {
      _controller.pause();
      setState(() => _isPlaying = false);
    }

    Navigator.push(
      context,
      PageRouteBuilder(
        fullscreenDialog: true,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullScreenVideoPlayer(
            url: widget.url,
            isMe: widget.isMe,
            videoId: widget.videoId, // ✅ تمرير videoId
            initialPosition: currentPosition,
            wasPlaying: wasPlaying,
            onClose: (position, isPlaying) {
              // ✅ استعادة الحالة عند العودة
              _controller.seekTo(position);
              if (isPlaying) {
                // ✅ إعادة تشغيل الفيديو باستخدام المدير
                Future.delayed(const Duration(milliseconds: 100), () {
                  VideoPlayerManager().playVideo(_controller, widget.videoId);
                  setState(() => _isPlaying = true);
                });
              } else {
                setState(() => _isPlaying = false);
              }
              setState(() {
                _currentPosition = position;
              });
            },
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return "0:00";
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    // ✅ إيقاف الفيديو عند الخروج من الويدجت
    if (_isPlaying) {
      _controller.pause();
      VideoPlayerManager().disposeController(widget.videoId);
    }
    _controller.removeListener(_updateProgress);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        width: 250,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            SizedBox(height: 8),
            Text("فشل تحميل الفيديو", style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: 250,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: widget.isMe ? const Color(0xFF075E54) : Colors.blue,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "جاري تحميل الفيديو...",
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 250,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
            GestureDetector(
              onTap: _togglePlayPause,
              child: Stack(
                children: [
                  AnimatedOpacity(
                    opacity: _showControls ? 0.4 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(color: Colors.black),
                  ),
                  if (!_isPlaying || _showControls)
                    Center(
                      child: GestureDetector(
                        onTap: _togglePlayPause,
                        child: AnimatedOpacity(
                          opacity: (!_isPlaying || _showControls) ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            child: Icon(
                              _isPlaying
                                  ? Icons.pause
                                  : (_currentPosition >= _totalDuration &&
                                        _totalDuration > Duration.zero)
                                  ? Icons.replay
                                  : Icons.play_arrow,
                              color: widget.isMe
                                  ? const Color(0xFF075E54)
                                  : Colors.blue,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              _formatDuration(_currentPosition),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: VideoProgressIndicator(
                                  _controller,
                                  allowScrubbing: true,
                                  colors: VideoProgressColors(
                                    playedColor: widget.isMe
                                        ? const Color(0xFF075E54)
                                        : Colors.blue,
                                    bufferedColor: Colors.white38,
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _formatDuration(_totalDuration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _restartVideo,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.replay,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _toggleMute,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isMuted ? Icons.volume_off : Icons.volume_up,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: GestureDetector(
                        onTap: _openFullScreen,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ شاشة ملء الشاشة - متكاملة مع VideoPlayerManager
class FullScreenVideoPlayer extends StatefulWidget {
  final String url;
  final bool isMe;
  final String videoId; // ✅ معرف الفيديو
  final Duration initialPosition;
  final bool wasPlaying;
  final Function(Duration position, bool isPlaying) onClose;

  const FullScreenVideoPlayer({
    super.key,
    required this.url,
    required this.isMe,
    required this.videoId,
    required this.initialPosition,
    required this.wasPlaying,
    required this.onClose,
  });

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _showControls = true;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));

      await _controller.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _totalDuration = _controller.value.duration;
      });

      // استعادة الموضع السابق
      await _controller.seekTo(widget.initialPosition);

      // استعادة حالة التشغيل
      if (widget.wasPlaying) {
        await _controller.play();
        _isPlaying = true;
      } else {
        _isPlaying = false;
      }

      _controller.addListener(_updateProgress);

      // إخفاء التحكمات بعد 3 ثواني
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isPlaying) {
          setState(() => _showControls = false);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hasError = true);
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
      VideoPlayerManager().pauseVideo();
    } else {
      if (_currentPosition >= _totalDuration) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
      // ✅ استخدام المدير لإيقاف أي فيديو آخر
      VideoPlayerManager().playVideo(_controller, widget.videoId);
    }
    setState(() => _isPlaying = !_isPlaying);
    _showControlsTemporarily();
  }

  void _restartVideo() async {
    await _controller.seekTo(Duration.zero);
    if (!_isPlaying) {
      await _controller.play();
      VideoPlayerManager().playVideo(_controller, widget.videoId);
      setState(() => _isPlaying = true);
    }
    setState(() {
      _currentPosition = Duration.zero;
      _showControls = true;
    });
    _showControlsTemporarily();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _controller.setVolume(_isMuted ? 0 : 1);
    });
    _showControlsTemporarily();
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _closeFullScreen() {
    // ✅ إيقاف الفيديو وإرجاع الحالة
    _controller.pause();
    widget.onClose(_currentPosition, _isPlaying);
    Navigator.pop(context);
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return "0:00";
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    // ✅ تنظيف الفيديو من المدير
    VideoPlayerManager().disposeController(widget.videoId);
    _controller.removeListener(_updateProgress);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text(
                "فشل تحميل الفيديو",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _initVideoPlayer();
                  });
                },
                child: const Text("إعادة المحاولة"),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _showControlsTemporarily,
        child: Stack(
          children: [
            // ✅ الفيديو يملأ الشاشة بالكامل
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

            // طبقة التحكمات
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                color: Colors.black.withOpacity(0.6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // الشريط العلوي
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // زر الرجوع
                            IconButton(
                              onPressed: _closeFullScreen,
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            // زر إعادة التشغيل وكتم الصوت
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _restartVideo,
                                  icon: const Icon(
                                    Icons.replay,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: _toggleMute,
                                  icon: Icon(
                                    _isMuted
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // زر التشغيل في المنتصف
                    if (!_isPlaying || _showControls)
                      Center(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          child: AnimatedOpacity(
                            opacity: (!_isPlaying || _showControls) ? 1.0 : 0.0,
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
                                color: widget.isMe
                                    ? const Color(0xFF075E54)
                                    : Colors.blue,
                                size: 50,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // الشريط السفلي
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // شريط التقدم
                            Row(
                              children: [
                                Text(
                                  _formatDuration(_currentPosition),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: VideoProgressIndicator(
                                      _controller,
                                      allowScrubbing: true,
                                      colors: VideoProgressColors(
                                        playedColor: widget.isMe
                                            ? const Color(0xFF075E54)
                                            : Colors.blue,
                                        bufferedColor: Colors.white38,
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDuration(_totalDuration),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // زر التصغير
                            GestureDetector(
                              onTap: _closeFullScreen,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.fullscreen_exit,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "خروج من ملء الشاشة",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
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
            ),
          ],
        ),
      ),
    );
  }
}
