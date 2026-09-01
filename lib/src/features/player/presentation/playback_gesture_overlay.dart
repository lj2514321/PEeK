import 'dart:async';

import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

enum _ActiveGesture { none, horizontalSeek, verticalBrightness, verticalVolume }

class PlaybackGestureOverlay extends StatefulWidget {
  const PlaybackGestureOverlay({
    super.key,
    required this.child,
    required this.position,
    required this.duration,
    required this.volume,
    required this.onVolumeChanged,
    required this.onSeek,
    required this.onPlayPause,
    required this.onToggleControls,
    required this.onSeekBack10,
    required this.onSeekForward10,
    this.isLocked = false,
    this.onLockChanged,
    this.enabled = true,
  });

  final Widget child;
  final Duration position;
  final Duration duration;
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleControls;
  final VoidCallback onSeekBack10;
  final VoidCallback onSeekForward10;
  final bool isLocked;
  final ValueChanged<bool>? onLockChanged;
  final bool enabled;

  @override
  State<PlaybackGestureOverlay> createState() => _PlaybackGestureOverlayState();
}

class _PlaybackGestureOverlayState extends State<PlaybackGestureOverlay> {
  _ActiveGesture _gesture = _ActiveGesture.none;

  // HUD values
  double _currentBrightness = 0.5;
  double _startBrightness = 0.5;
  double _currentVolume = 1.0;
  double _startVolume = 1.0;
  Duration _targetSeekPosition = Duration.zero;
  Duration _seekStartOrigin = Duration.zero;
  Offset _dragStart = Offset.zero;

  // Feedback animations
  String? _doubleTapSide; // 'left' or 'right'
  Timer? _doubleTapTimer;
  Timer? _hudDismissTimer;
  bool _showHud = false;

  @override
  void initState() {
    super.initState();
    _currentVolume = widget.volume;
    _initBrightness();
  }

  @override
  void didUpdateWidget(PlaybackGestureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_gesture != _ActiveGesture.verticalVolume) {
      _currentVolume = widget.volume;
    }
  }

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    _hudDismissTimer?.cancel();
    super.dispose();
  }

  Future<void> _initBrightness() async {
    try {
      final b = await ScreenBrightness.instance.application;
      if (mounted) {
        setState(() => _currentBrightness = b.clamp(0.0, 1.0));
      }
    } catch (_) {
      // Running on platform or test environment without screen brightness support
    }
  }

  void _onDoubleTapDown(TapDownDetails details, BoxConstraints constraints) {
    if (widget.isLocked || !widget.enabled) return;

    final x = details.localPosition.dx;
    final width = constraints.maxWidth;

    if (x < width * 0.35) {
      widget.onSeekBack10();
      _triggerDoubleTapFeedback('left');
    } else if (x > width * 0.65) {
      widget.onSeekForward10();
      _triggerDoubleTapFeedback('right');
    } else {
      widget.onPlayPause();
    }
  }

  void _triggerDoubleTapFeedback(String side) {
    _doubleTapTimer?.cancel();
    setState(() => _doubleTapSide = side);
    _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _doubleTapSide = null);
    });
  }

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    if (widget.isLocked || !widget.enabled) return;

    _dragStart = details.localPosition;
    _startVolume = widget.volume;
    _currentVolume = widget.volume;
    _startBrightness = _currentBrightness;
    _seekStartOrigin = widget.position;
    _targetSeekPosition = widget.position;
    _gesture = _ActiveGesture.none;
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (widget.isLocked || !widget.enabled) return;

    final delta = details.localPosition - _dragStart;

    if (_gesture == _ActiveGesture.none) {
      // Determine dominant direction
      if (delta.dx.abs() > 18 && delta.dx.abs() > delta.dy.abs() * 1.4) {
        _gesture = _ActiveGesture.horizontalSeek;
      } else if (delta.dy.abs() > 18 && delta.dy.abs() > delta.dx.abs() * 1.4) {
        final startX = _dragStart.dx;
        if (startX < constraints.maxWidth * 0.5) {
          _gesture = _ActiveGesture.verticalBrightness;
        } else {
          _gesture = _ActiveGesture.verticalVolume;
        }
      }
    }

    if (_gesture == _ActiveGesture.none) return;

    setState(() {
      _showHud = true;
    });
    _hudDismissTimer?.cancel();

    switch (_gesture) {
      case _ActiveGesture.horizontalSeek:
        if (widget.duration.inMilliseconds <= 0) return;
        // 100px drag = ~30 seconds seek
        final secondsDelta = (delta.dx / constraints.maxWidth) * 120;
        final targetMs = (_seekStartOrigin.inMilliseconds + (secondsDelta * 1000).toInt())
            .clamp(0, widget.duration.inMilliseconds);
        setState(() {
          _targetSeekPosition = Duration(milliseconds: targetMs);
        });
        break;

      case _ActiveGesture.verticalBrightness:
        // Drag upwards increases brightness
        final dragFraction = -delta.dy / (constraints.maxHeight * 0.65);
        final newBrightness = (_startBrightness + dragFraction).clamp(0.0, 1.0);
        setState(() {
          _currentBrightness = newBrightness;
        });
        try {
          ScreenBrightness.instance.setApplicationScreenBrightness(newBrightness);
        } catch (_) {}
        break;

      case _ActiveGesture.verticalVolume:
        // Drag upwards increases volume
        final dragFraction = -delta.dy / (constraints.maxHeight * 0.65);
        final newVolume = (_startVolume + dragFraction).clamp(0.0, 1.0);
        setState(() {
          _currentVolume = newVolume;
        });
        widget.onVolumeChanged(newVolume);
        break;

      case _ActiveGesture.none:
        break;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_gesture == _ActiveGesture.horizontalSeek) {
      widget.onSeek(_targetSeekPosition);
    }
    _gesture = _ActiveGesture.none;
    _hudDismissTimer?.cancel();
    _hudDismissTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _showHud = false);
      }
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Underlying content (video player, etc.)
            widget.child,

            // Gesture detection layer
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (!widget.isLocked) {
                    widget.onToggleControls();
                  }
                },
                onDoubleTapDown: (details) => _onDoubleTapDown(details, constraints),
                onPanStart: (details) => _onPanStart(details, constraints),
                onPanUpdate: (details) => _onPanUpdate(details, constraints),
                onPanEnd: _onPanEnd,
                onPanCancel: () {
                  _gesture = _ActiveGesture.none;
                  setState(() => _showHud = false);
                },
                child: const SizedBox.expand(),
              ),
            ),

            // Double tap feedback
            if (_doubleTapSide != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: _doubleTapSide == 'left'
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          _doubleTapSide == 'left'
                              ? Icons.fast_rewind_rounded
                              : Icons.fast_forward_rounded,
                          size: 40,
                          color: AppColors.spotlight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Gesture HUD (Brightness, Volume, Seek)
            if (_showHud)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: _buildHud(),
                  ),
                ),
              ),

            // Floating Lock Toggle (especially for mobile touch safety)
            if (widget.onLockChanged != null &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS ||
                    kDebugMode))
              Positioned(
                right: 20,
                top: constraints.maxHeight * 0.45,
                child: GestureDetector(
                  onTap: () => widget.onLockChanged!(!widget.isLocked),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isLocked
                            ? AppColors.spotlight
                            : Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.isLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 24,
                      color: widget.isLocked
                          ? AppColors.spotlight
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHud() {
    switch (_gesture) {
      case _ActiveGesture.horizontalSeek:
        final diff = _targetSeekPosition - _seekStartOrigin;
        final isForward = diff.inMilliseconds >= 0;
        final sign = isForward ? '+' : '-';
        final absDiff = diff.abs();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: AppGlass.visionOSDecoration(
            radius: 20,
            elevated: true,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                size: 36,
                color: AppColors.spotlight,
              ),
              const SizedBox(height: 10),
              Text(
                '${_formatDuration(_targetSeekPosition)} / ${_formatDuration(widget.duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '[$sign${_formatDuration(absDiff)}]',
                style: TextStyle(
                  color: AppColors.spotlight.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );

      case _ActiveGesture.verticalBrightness:
        final percent = (_currentBrightness * 100).toInt();
        return _buildLevelHud(
          icon: _currentBrightness > 0.5
              ? Icons.brightness_high_rounded
              : (_currentBrightness > 0.2
                  ? Icons.brightness_medium_rounded
                  : Icons.brightness_low_rounded),
          label: '亮度',
          percent: percent,
          value: _currentBrightness,
        );

      case _ActiveGesture.verticalVolume:
        final percent = (_currentVolume * 100).toInt();
        return _buildLevelHud(
          icon: _currentVolume <= 0
              ? Icons.volume_off_rounded
              : (_currentVolume > 0.5
                  ? Icons.volume_up_rounded
                  : Icons.volume_down_rounded),
          label: '音量',
          percent: percent,
          value: _currentVolume,
        );

      case _ActiveGesture.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLevelHud({
    required IconData icon,
    required String label,
    required int percent,
    required double value,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: AppGlass.visionOSDecoration(
        radius: 20,
        elevated: true,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.spotlight),
          const SizedBox(height: 10),
          Text(
            '$label $percent%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.spotlight),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}
