import 'dart:async';

import 'package:better_player_plus/src/controls/better_player_ui.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Configuration for gesture-based controls
class BetterPlayerGestureConfiguration {
  const BetterPlayerGestureConfiguration({
    this.enableVolumeSwipe = true,
    this.enableBrightnessSwipe = true,
    this.enableSeekSwipe = true,
    this.volumeSwipeSensitivity = 0.5,
    this.brightnessSwipeSensitivity = 0.5,
    this.seekSwipeSensitivity = 1.0,
    this.minimumSwipeDistance = 10.0,
    this.feedbackDuration = const Duration(milliseconds: 800),
    this.swipeAreaWidthPercentage = 0.2, // Reduced from 0.35 to 0.2 (20% each side)
  });

  /// Enable volume control via vertical swipe on right side
  final bool enableVolumeSwipe;

  /// Enable brightness control via vertical swipe on left side
  final bool enableBrightnessSwipe;

  /// Enable seek control via horizontal swipe
  final bool enableSeekSwipe;

  /// Volume swipe sensitivity (0.1 - 2.0)
  final double volumeSwipeSensitivity;

  /// Brightness swipe sensitivity (0.1 - 2.0)
  final double brightnessSwipeSensitivity;

  /// Seek swipe sensitivity (0.1 - 2.0)
  final double seekSwipeSensitivity;

  /// Minimum distance to trigger swipe gesture
  final double minimumSwipeDistance;

  /// Duration to show feedback overlay
  final Duration feedbackDuration;

  /// Width percentage of left/right swipe areas (0.2 - 0.5)
  final double swipeAreaWidthPercentage;
}

/// Types of gesture feedback
enum GestureFeedbackType { volume, brightness, seekForward, seekBackward }

/// Widget that handles gesture-based controls for video player
class BetterPlayerGestureHandler extends StatefulWidget {
  const BetterPlayerGestureHandler({
    required this.child,
    required this.configuration,
    required this.onVolumeChanged,
    required this.onBrightnessChanged,
    required this.onSeek,
    required this.currentVolume,
    required this.currentBrightness,
    this.controlsVisible = true, // Whether controls are currently visible
    this.onTap, // Callback to show controls overlay on tap
    super.key,
  });

  final Widget child;
  final BetterPlayerGestureConfiguration configuration;
  final Function(double volume) onVolumeChanged;
  final Function(double brightness) onBrightnessChanged;
  final Function(Duration position) onSeek;
  final double currentVolume;
  final double currentBrightness;
  final bool controlsVisible;
  final VoidCallback? onTap;

  @override
  State<BetterPlayerGestureHandler> createState() => _BetterPlayerGestureHandlerState();
}

class _BetterPlayerGestureHandlerState extends State<BetterPlayerGestureHandler> {
  bool _isGestureActive = false;
  GestureFeedbackType? _currentGesture;
  double _gestureValue = 0.0;
  Offset? _dragStartPosition;
  double _initialValue = 0.0;
  Timer? _feedbackTimer;

  // Track if we've moved enough to be considered a drag (not a tap)
  bool _hasMovedEnough = false;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details, bool isLeftSide) {
    final config = widget.configuration;

    if (isLeftSide && !config.enableBrightnessSwipe) return;
    if (!isLeftSide && !config.enableVolumeSwipe) return;

    _dragStartPosition = details.localPosition;
    _hasMovedEnough = false; // Don't activate gesture until we move enough

    // CRITICAL FIX: Get the CURRENT value from widget props (which were updated by previous gestures)
    if (isLeftSide) {
      _currentGesture = GestureFeedbackType.brightness;
      _initialValue = widget.currentBrightness;
    } else {
      _currentGesture = GestureFeedbackType.volume;
      _initialValue = widget.currentVolume;
    }

    // DON'T call setState or set _isGestureActive yet - wait for actual movement
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, bool isLeftSide, double screenHeight) {
    if (_dragStartPosition == null) return;

    final config = widget.configuration;
    // FIX: Correct direction - swipe UP should increase, swipe DOWN should decrease
    final double delta = details.localPosition.dy - _dragStartPosition!.dy;

    // Check if we've moved enough to be considered a real drag (not a tap)
    if (!_hasMovedEnough) {
      if (delta.abs() < config.minimumSwipeDistance) {
        return; // Still below threshold, could be a tap
      }
      // We've moved enough - activate the gesture now!
      _hasMovedEnough = true;
      _isGestureActive = true;
      _gestureValue = _initialValue; // Start from initial value
      setState(() {});
    }

    if (!_isGestureActive) return;

    // Cancel any pending hide timer while actively dragging
    _feedbackTimer?.cancel();

    final double sensitivity = isLeftSide ? config.brightnessSwipeSensitivity : config.volumeSwipeSensitivity;

    // Negative delta = swipe UP = INCREASE value
    // Positive delta = swipe DOWN = DECREASE value
    final double normalizedDelta = -(delta / screenHeight) * sensitivity;
    final double newValue = (_initialValue + normalizedDelta).clamp(0.0, 1.0);

    setState(() {
      _gestureValue = newValue;
    });

    if (isLeftSide) {
      widget.onBrightnessChanged(newValue);
    } else {
      widget.onVolumeChanged(newValue);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragStartPosition = null;
    _hasMovedEnough = false;

    // Only hide feedback if gesture was actually activated
    if (_isGestureActive) {
      _hideFeedbackAfterDelay();
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!widget.configuration.enableSeekSwipe) return;

    _dragStartPosition = details.localPosition;
    _hasMovedEnough = false; // Don't activate until we move enough
    _currentGesture = GestureFeedbackType.seekForward; // Temporary
    _initialValue = 0.0;

    // DON'T call setState or set _isGestureActive yet - wait for actual movement
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (_dragStartPosition == null) return;

    final config = widget.configuration;
    final double delta = details.localPosition.dx - _dragStartPosition!.dx;

    // Check if we've moved enough to be considered a real drag (not a tap)
    if (!_hasMovedEnough) {
      if (delta.abs() < config.minimumSwipeDistance) {
        return; // Still below threshold, could be a tap
      }
      // We've moved enough - activate the gesture now!
      _hasMovedEnough = true;
      _isGestureActive = true;
      _gestureValue = 0.0;
      setState(() {});
    }

    if (!_isGestureActive) return;

    // Cancel any pending hide timer while actively dragging
    _feedbackTimer?.cancel();

    final double sensitivity = config.seekSwipeSensitivity;
    final double normalizedDelta = (delta / screenWidth) * sensitivity;

    setState(() {
      _gestureValue = normalizedDelta * 100; // Convert to seconds
      _currentGesture = normalizedDelta > 0 ? GestureFeedbackType.seekForward : GestureFeedbackType.seekBackward;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    // Only perform seek if gesture was actually activated
    if (_isGestureActive && _gestureValue != 0) {
      // Preserve the sign: positive for forward, negative for backward
      final seekSeconds = _gestureValue.round();
      final seekDuration = Duration(seconds: seekSeconds);
      widget.onSeek(seekDuration);
    }

    _dragStartPosition = null;
    _hasMovedEnough = false;

    // Only hide feedback if gesture was actually activated
    if (_isGestureActive) {
      _hideFeedbackAfterDelay();
    }
  }

  void _hideFeedbackAfterDelay() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(widget.configuration.feedbackDuration, () {
      if (mounted) {
        setState(() {
          _isGestureActive = false;
          _currentGesture = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final swipeAreaWidth = size.width * widget.configuration.swipeAreaWidthPercentage;

    // Define safe zones to avoid blocking control bars
    // Top bar is typically 50-80px, bottom bar is 80-100px
    const double topSafeZone = 80.0;
    const double bottomSafeZone = 100.0;

    return Stack(
      children: [
        // Original child (controls) - put FIRST so gesture zones can overlay
        widget.child,

        // Left side - Brightness control (only active when controls are hidden)
        if (widget.configuration.enableBrightnessSwipe && !widget.controlsVisible)
          Positioned(
            left: 0,
            top: topSafeZone, // Don't cover top bar
            bottom: bottomSafeZone, // Don't cover bottom bar
            width: swipeAreaWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // Capture all events in this area
              onTap: () {
                // Forward tap to show controls overlay
                widget.onTap?.call();
              },
              onVerticalDragStart: (details) => _onVerticalDragStart(details, true),
              onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, true, size.height),
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Right side - Volume control (only active when controls are hidden)
        if (widget.configuration.enableVolumeSwipe && !widget.controlsVisible)
          Positioned(
            right: 0,
            top: topSafeZone, // Don't cover top bar
            bottom: bottomSafeZone, // Don't cover bottom bar
            width: swipeAreaWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // Capture all events in this area
              onTap: () {
                // Forward tap to show controls overlay
                widget.onTap?.call();
              },
              onVerticalDragStart: (details) => _onVerticalDragStart(details, false),
              onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, false, size.height),
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Bottom center - Seek control (only active when controls are hidden)
        // Small horizontal strip at the bottom for seek gestures
        if (widget.configuration.enableSeekSwipe && !widget.controlsVisible)
          Positioned(
            left: swipeAreaWidth, // Start after left gesture zone
            right: swipeAreaWidth, // End before right gesture zone
            bottom: 20, // Small strip near bottom
            height: 60, // Small height to not interfere with buttons
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // Capture all events in this area
              onTap: () {
                // Forward tap to show controls overlay
                widget.onTap?.call();
              },
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: (details) => _onHorizontalDragUpdate(details, size.width),
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Feedback overlay (always on top)
        if (_isGestureActive && _currentGesture != null) _buildFeedbackOverlay(),
      ],
    );
  }

  Widget _buildFeedbackOverlay() {
    return Center(child: _buildFeedbackContent());
  }

  Widget _buildFeedbackContent() {
    switch (_currentGesture!) {
      case GestureFeedbackType.volume:
        final percentage = (_gestureValue * 100).round();
        return BetterPlayerGesturePill(
          icon: percentage == 0 ? PhosphorIcons.speakerSlash() : PhosphorIcons.speakerHigh(),
          label: '$percentage%',
          value: _gestureValue,
        );
      case GestureFeedbackType.brightness:
        return BetterPlayerGesturePill(
          icon: PhosphorIcons.sun(),
          label: '${(_gestureValue * 100).round()}%',
          value: _gestureValue,
        );
      case GestureFeedbackType.seekForward:
      case GestureFeedbackType.seekBackward:
        final forward = _currentGesture == GestureFeedbackType.seekForward;
        return BetterPlayerGesturePill(
          icon: forward ? PhosphorIcons.fastForward() : PhosphorIcons.rewind(),
          label: '${forward ? '+' : '-'}${_gestureValue.abs().round()}s',
        );
    }
  }
}
