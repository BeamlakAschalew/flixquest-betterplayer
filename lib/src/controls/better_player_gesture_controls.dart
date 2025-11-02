import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

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
    Key? key,
    required this.child,
    required this.configuration,
    required this.onVolumeChanged,
    required this.onBrightnessChanged,
    required this.onSeek,
    required this.currentVolume,
    required this.currentBrightness,
  }) : super(key: key);

  final Widget child;
  final BetterPlayerGestureConfiguration configuration;
  final Function(double volume) onVolumeChanged;
  final Function(double brightness) onBrightnessChanged;
  final Function(Duration position) onSeek;
  final double currentVolume;
  final double currentBrightness;

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

    // DEBUG: Log gesture detection
    print(
      '🎯 BetterPlayer Gesture: Vertical drag started on ${isLeftSide ? "LEFT (Brightness)" : "RIGHT (Volume)"} side',
    );

    _dragStartPosition = details.localPosition;
    _hasMovedEnough = false; // Don't activate gesture until we move enough

    // CRITICAL FIX: Get the CURRENT value from widget props (which were updated by previous gestures)
    if (isLeftSide) {
      _currentGesture = GestureFeedbackType.brightness;
      _initialValue = widget.currentBrightness;
      print('🎯 Starting brightness gesture from: ${_initialValue.toStringAsFixed(2)}');
    } else {
      _currentGesture = GestureFeedbackType.volume;
      _initialValue = widget.currentVolume;
      print('🎯 Starting volume gesture from: ${_initialValue.toStringAsFixed(2)}');
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

    // DEBUG: Log gesture value
    print('🎯 BetterPlayer Gesture: ${isLeftSide ? "Brightness" : "Volume"} delta=$delta, initial=$_initialValue');

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
    print('🎯 BetterPlayer: Building GestureHandler widget');
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

        // Left side - Brightness control
        if (widget.configuration.enableBrightnessSwipe)
          Positioned(
            left: 0,
            top: topSafeZone, // Don't cover top bar
            bottom: bottomSafeZone, // Don't cover bottom bar
            width: swipeAreaWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild, // Only intercept vertical drags, let taps through
              onVerticalDragStart: (details) => _onVerticalDragStart(details, true),
              onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, true, size.height),
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Right side - Volume control
        if (widget.configuration.enableVolumeSwipe)
          Positioned(
            right: 0,
            top: topSafeZone, // Don't cover top bar
            bottom: bottomSafeZone, // Don't cover bottom bar
            width: swipeAreaWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild, // Only intercept vertical drags, let taps through
              onVerticalDragStart: (details) => _onVerticalDragStart(details, false),
              onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, false, size.height),
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Container(color: Colors.transparent),
            ),
          ),

        // NOTE: Center seek control removed - it was blocking taps to show/hide controls
        // If you want seek gestures, add them back with HitTestBehavior.translucent

        // Feedback overlay (always on top)
        if (_isGestureActive && _currentGesture != null) _buildFeedbackOverlay(),
      ],
    );
  }

  Widget _buildFeedbackOverlay() {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final surfaceColor = theme.colorScheme.surface;
    final onSurfaceColor = theme.colorScheme.onSurface;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryColor.withOpacity(0.3), width: 2),
        ),
        child: _buildFeedbackContent(primaryColor, onSurfaceColor),
      ),
    );
  }

  Widget _buildFeedbackContent(Color primaryColor, Color onSurfaceColor) {
    switch (_currentGesture!) {
      case GestureFeedbackType.volume:
        return _buildVolumeIndicator(primaryColor, onSurfaceColor);
      case GestureFeedbackType.brightness:
        return _buildBrightnessIndicator(primaryColor, onSurfaceColor);
      case GestureFeedbackType.seekForward:
      case GestureFeedbackType.seekBackward:
        return _buildSeekIndicator(primaryColor, onSurfaceColor);
    }
  }

  Widget _buildVolumeIndicator(Color primaryColor, Color textColor) {
    final percentage = (_gestureValue * 100).round();
    final isMuted = percentage == 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isMuted ? Icons.volume_off : Icons.volume_up, color: primaryColor, size: 36),
        const SizedBox(height: 12),
        SizedBox(
          width: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _gestureValue,
              backgroundColor: textColor.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$percentage%',
          style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildBrightnessIndicator(Color primaryColor, Color textColor) {
    final percentage = (_gestureValue * 100).round();

    // Use more granular brightness icons
    IconData brightnessIcon;
    if (percentage < 20) {
      brightnessIcon = Icons.brightness_low;
    } else if (percentage < 70) {
      brightnessIcon = Icons.brightness_medium;
    } else {
      brightnessIcon = Icons.brightness_high;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(brightnessIcon, color: primaryColor, size: 36),
        const SizedBox(height: 12),
        SizedBox(
          width: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _gestureValue,
              backgroundColor: textColor.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$percentage%',
          style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildSeekIndicator(Color primaryColor, Color textColor) {
    final seconds = _gestureValue.abs().round();
    final isForward = _currentGesture == GestureFeedbackType.seekForward;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isForward ? Icons.fast_forward : Icons.fast_rewind, color: primaryColor, size: 36),
        const SizedBox(width: 12),
        Text(
          '${isForward ? '+' : '-'}${seconds}s',
          style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
