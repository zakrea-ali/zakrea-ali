// lib/screens/chat_actions/UniversalAudioPlayer.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

// ✅ مدير عالمي للتحكم بالمشغلات الصوتية
class AudioPlayerManager {
  static final AudioPlayerManager _instance = AudioPlayerManager._internal();
  factory AudioPlayerManager() => _instance;
  AudioPlayerManager._internal();

  final Set<_UniversalAudioPlayerState> _activePlayers = {};

  void register(_UniversalAudioPlayerState player) {
    _activePlayers.add(player);
  }

  void unregister(_UniversalAudioPlayerState player) {
    _activePlayers.remove(player);
  }

  void stopOthers(_UniversalAudioPlayerState currentPlayer) {
    for (var player in _activePlayers) {
      if (player != currentPlayer && player._isPlaying) {
        player._stopPlayback();
      }
    }
  }

  void stopAll() {
    for (var player in _activePlayers.toList()) {
      player._stopPlayback();
    }
  }
}

class UniversalAudioPlayer extends StatefulWidget {
  final String audioUrl;
  final bool isMe;
  final Color? primaryColor;
  final VoidCallback? onPlayStateChanged;
  final VoidCallback? onError;
  final double maxWidth;

  const UniversalAudioPlayer({
    Key? key,
    required this.audioUrl,
    required this.isMe,
    this.primaryColor,
    this.onPlayStateChanged,
    this.onError,
    this.maxWidth = 250,
  }) : super(key: key);

  @override
  State<UniversalAudioPlayer> createState() => _UniversalAudioPlayerState();
}

class _UniversalAudioPlayerState extends State<UniversalAudioPlayer> {
  AudioPlayer? _player;
  String? _localFilePath;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  // ✅ تصحيح النوع: durationStream ينبعث بـ Duration? (قد يكون null)
  StreamSubscription<Duration?>? _durationSubscription;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    AudioPlayerManager().register(this);
    _initPlayer();
  }

  @override
  void didUpdateWidget(UniversalAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      _disposePlayer();
      _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _isPlaying = false;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;
        _isDownloading = false;
      });
    }

    _player = AudioPlayer();

    // مراقبة التقدم
    _positionSubscription = _player!.positionStream.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });

    // مراقبة حالة المشغل
    _playerStateSubscription = _player!.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing;
      if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
        widget.onPlayStateChanged?.call();
        if (playing) {
          AudioPlayerManager().stopOthers(this);
        }
      }
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
          _currentPosition = Duration.zero;
        });
        _player?.seek(Duration.zero);
      }
    });

    // ✅ مراقبة المدة (مع تصحيح النوع)
    // محاولة قراءة المدة الحالية فوراً (قد تكون null)
    try {
      final duration = _player!.duration;
      if (duration != null && mounted) {
        setState(() => _totalDuration = duration);
      }
    } catch (_) {}

    // الاستماع لتحديثات المدة (قيمتها قد تكون null)
    _durationSubscription = _player!.durationStream.listen(
      (dur) {
        if (mounted && dur != null) {
          setState(() => _totalDuration = dur);
        }
      },
      onError: (e) {
        // في حال فشل تدفق المدة، نتعامل معه بصمت
        print("Error reading duration stream: $e");
      },
    );

    try {
      await _player!.setUrl(widget.audioUrl);
      setState(() => _isLoading = false);
    } catch (e) {
      await _downloadAndPlay();
    }
  }

  Future<void> _downloadAndPlay() async {
    setState(() => _isDownloading = true);
    try {
      final extension = _getFileExtension(widget.audioUrl);
      final dir = await getTemporaryDirectory();
      _localFilePath =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final response = await http.get(Uri.parse(widget.audioUrl));
      if (response.statusCode == 200) {
        await File(_localFilePath!).writeAsBytes(response.bodyBytes);
        await _player!.setFilePath(_localFilePath!);
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _isDownloading = false);
      _handleError('فشل تحميل الملف الصوتي');
    }
  }

  String _getFileExtension(String url) {
    if (url.contains('.opus')) return 'opus';
    if (url.contains('.mp3')) return 'mp3';
    if (url.contains('.m4a')) return 'm4a';
    if (url.contains('.wav')) return 'wav';
    return 'bin';
  }

  Future<void> _togglePlayPause() async {
    if (_hasError) {
      _initPlayer();
      return;
    }
    if (_isLoading || _isDownloading) return;
    if (_player == null) return;

    try {
      if (_isPlaying) {
        await _player!.pause();
      } else {
        if (_currentPosition >= _totalDuration &&
            _totalDuration > Duration.zero) {
          await _player!.seek(Duration.zero);
        }
        await _player!.play();
      }
    } catch (e) {
      _handleError('حدث خطأ أثناء التشغيل');
    }
  }

  Future<void> _seekTo(Duration position) async {
    if (_player != null) await _player!.seek(position);
  }

  void _handleError(String msg) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = msg;
        _isLoading = false;
        _isDownloading = false;
      });
    }
    widget.onError?.call();
  }

  void _stopPlayback() {
    if (_isPlaying && _player != null) {
      _player!.pause();
    }
  }

  void _disposePlayer() {
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _player?.dispose();
    _player = null;
    if (_localFilePath != null) {
      File(_localFilePath!).delete().catchError((_) {});
      _localFilePath = null;
    }
  }

  String _formatDuration(Duration d) {
    if (d <= Duration.zero) return '0:00';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  double _getProgress() {
    if (_totalDuration <= Duration.zero) return 0;
    return _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
  }

  @override
  void dispose() {
    AudioPlayerManager().unregister(this);
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor =
        widget.primaryColor ??
        (widget.isMe ? const Color(0xff25D366) : const Color(0xFF075E54));

    return Container(
      constraints: BoxConstraints(maxWidth: widget.maxWidth, minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isMe ? const Color(0xffdcf8c6) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hasError ? Colors.red : primaryColor,
                  ),
                  child: Center(
                    child: (_isLoading || _isDownloading)
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : _hasError
                        ? const Icon(
                            Icons.refresh,
                            color: Colors.white,
                            size: 22,
                          )
                        : Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 26,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor: primaryColor,
                        inactiveTrackColor: Colors.grey.shade300,
                        thumbColor: primaryColor,
                      ),
                      child: Slider(
                        value: _getProgress(),
                        onChanged: (_hasError || _isLoading || _isDownloading)
                            ? null
                            : (value) {
                                final newPosition = Duration(
                                  milliseconds:
                                      (value * _totalDuration.inMilliseconds)
                                          .toInt(),
                                );
                                _seekTo(newPosition);
                              },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          _formatDuration(_totalDuration),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
