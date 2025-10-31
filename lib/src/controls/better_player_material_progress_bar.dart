import 'dart:async';
import 'package:better_player_plus/better_player.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';

class BetterPlayerMaterialVideoProgressBar extends StatefulWidget {
  BetterPlayerMaterialVideoProgressBar(
    this.controller,
    this.betterPlayerController, {
    BetterPlayerProgressColors? colors,
    this.onDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onTapDown,
    this.showThumbnailPreview = true,
    Key? key,
  }) : colors = colors ?? BetterPlayerProgressColors(),
       super(key: key);

  final VideoPlayerController? controller;
  final BetterPlayerController? betterPlayerController;
  final BetterPlayerProgressColors colors;
  final Function()? onDragStart;
  final Function()? onDragEnd;
  final Function()? onDragUpdate;
  final Function()? onTapDown;
  final bool showThumbnailPreview;

  @override
  _VideoProgressBarState createState() {
    return _VideoProgressBarState();
  }
}

class _VideoProgressBarState extends State<BetterPlayerMaterialVideoProgressBar> {
  _VideoProgressBarState() {
    listener = () {
      if (mounted) setState(() {});
    };
  }

  late VoidCallback listener;
  bool _controllerWasPlaying = false;

  VideoPlayerController? get controller => widget.controller;

  BetterPlayerController? get betterPlayerController => widget.betterPlayerController;

  bool shouldPlayAfterDragEnd = false;
  Duration? lastSeek;
  Timer? _updateBlockTimer;

  // Thumbnail preview state
  bool _showThumbnailPreview = false;
  Offset? _dragPosition;
  Duration? _previewPosition;
  Timer? _previewLoadTimer;
  Duration? _lastPreviewLoadPosition;

  @override
  void initState() {
    super.initState();
    controller!.addListener(listener);
  }

  @override
  void deactivate() {
    controller!.removeListener(listener);
    _cancelUpdateBlockTimer();
    _cancelPreviewLoadTimer();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final bool enableProgressBarDrag =
        betterPlayerController!.betterPlayerConfiguration.controlsConfiguration.enableProgressBarDrag;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onHorizontalDragStart: (DragStartDetails details) {
            if (!controller!.value.initialized || !enableProgressBarDrag) {
              return;
            }

            _controllerWasPlaying = controller!.value.isPlaying;
            if (_controllerWasPlaying) {
              controller!.pause();
            }

            if (widget.showThumbnailPreview) {
              setState(() {
                _showThumbnailPreview = true;
                _dragPosition = details.globalPosition;
                _updatePreviewPosition(details.globalPosition);
                _schedulePreviewLoad();
              });
            }

            if (widget.onDragStart != null) {
              widget.onDragStart!();
            }
          },
          onHorizontalDragUpdate: (DragUpdateDetails details) {
            if (!controller!.value.initialized || !enableProgressBarDrag) {
              return;
            }

            seekToRelativePosition(details.globalPosition);

            if (widget.showThumbnailPreview) {
              setState(() {
                _dragPosition = details.globalPosition;
                _updatePreviewPosition(details.globalPosition);
                _schedulePreviewLoad();
              });
            }

            if (widget.onDragUpdate != null) {
              widget.onDragUpdate!();
            }
          },
          onHorizontalDragEnd: (DragEndDetails details) {
            if (!enableProgressBarDrag) {
              return;
            }

            if (_controllerWasPlaying) {
              betterPlayerController?.play();
              shouldPlayAfterDragEnd = true;
            }
            _setupUpdateBlockTimer();

            if (widget.showThumbnailPreview) {
              setState(() {
                _showThumbnailPreview = false;
                _dragPosition = null;
                _previewPosition = null;
                _cancelPreviewLoadTimer();
              });
            }

            if (widget.onDragEnd != null) {
              widget.onDragEnd!();
            }
          },
          onTapDown: (TapDownDetails details) {
            if (!controller!.value.initialized || !enableProgressBarDrag) {
              return;
            }
            seekToRelativePosition(details.globalPosition);
            _setupUpdateBlockTimer();
            if (widget.onTapDown != null) {
              widget.onTapDown!();
            }
          },
          child: Center(
            child: Container(
              height: MediaQuery.of(context).size.height / 2,
              width: MediaQuery.of(context).size.width,
              color: Colors.transparent,
              child: CustomPaint(painter: _ProgressBarPainter(_getValue(), widget.colors, betterPlayerController!)),
            ),
          ),
        ),
        // Thumbnail preview widget
        if (_showThumbnailPreview && _dragPosition != null && _previewPosition != null) _buildThumbnailPreview(context),
      ],
    );
  }

  void _setupUpdateBlockTimer() {
    _updateBlockTimer = Timer(const Duration(milliseconds: 1000), () {
      lastSeek = null;
      _cancelUpdateBlockTimer();
    });
  }

  void _cancelUpdateBlockTimer() {
    _updateBlockTimer?.cancel();
    _updateBlockTimer = null;
  }

  VideoPlayerValue _getValue() {
    if (lastSeek != null) {
      return controller!.value.copyWith(position: lastSeek);
    } else {
      return controller!.value;
    }
  }

  void seekToRelativePosition(Offset globalPosition) async {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject != null) {
      final box = renderObject as RenderBox;
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = tapPos.dx / box.size.width;
      if (relative > 0) {
        final Duration position = controller!.value.duration! * relative;
        lastSeek = position;
        await betterPlayerController!.seekTo(position);
        onFinishedLastSeek();
        if (relative >= 1) {
          lastSeek = controller!.value.duration;
          await betterPlayerController!.seekTo(controller!.value.duration!);
          onFinishedLastSeek();
        }
      }
    }
  }

  void onFinishedLastSeek() {
    if (shouldPlayAfterDragEnd) {
      shouldPlayAfterDragEnd = false;
      betterPlayerController?.play();
    }
  }

  void _updatePreviewPosition(Offset globalPosition) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject != null) {
      final box = renderObject as RenderBox;
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = tapPos.dx / box.size.width;
      if (relative >= 0 && relative <= 1) {
        final Duration position = controller!.value.duration! * relative;
        _previewPosition = position;
      }
    }
  }

  /// Check if a position is in the buffered range
  bool _isPositionBuffered(Duration position) {
    if (controller == null || !controller!.value.initialized) {
      return false;
    }

    for (final DurationRange range in controller!.value.buffered) {
      if (position >= range.start && position <= range.end) {
        return true;
      }
    }
    return false;
  }

  /// Schedule progressive loading for unbuffered positions
  void _schedulePreviewLoad() {
    // Cancel any existing timer
    _cancelPreviewLoadTimer();

    if (_previewPosition == null) return;

    // If position is already buffered, no need to load
    if (_isPositionBuffered(_previewPosition!)) {
      return;
    }

    // If we already tried to load this position recently, don't retry immediately
    if (_lastPreviewLoadPosition != null &&
        (_previewPosition! - _lastPreviewLoadPosition!).abs() < const Duration(seconds: 2)) {
      return;
    }

    // Schedule loading after user hovers for 800ms on unbuffered region
    _previewLoadTimer = Timer(const Duration(milliseconds: 800), () {
      if (_previewPosition != null && !_isPositionBuffered(_previewPosition!)) {
        _loadPreviewFrame(_previewPosition!);
      }
    });
  }

  /// Load a preview frame by temporarily seeking to that position
  Future<void> _loadPreviewFrame(Duration position) async {
    if (controller == null || !controller!.value.initialized) {
      return;
    }

    _lastPreviewLoadPosition = position;

    try {
      // Store current position
      final currentPosition = controller!.value.position;

      // Briefly seek to the preview position to trigger buffering
      await controller!.seekTo(position);

      // Wait a moment for the frame to load
      await Future.delayed(const Duration(milliseconds: 300));

      // Seek back to original position (or close to it)
      // This allows the frame to stay in buffer while user is still hovering
      if (_showThumbnailPreview && mounted) {
        await controller!.seekTo(currentPosition);
      }
    } catch (e) {
      // Ignore errors during preview loading
    }
  }

  void _cancelPreviewLoadTimer() {
    _previewLoadTimer?.cancel();
    _previewLoadTimer = null;
  }

  Widget _buildThumbnailPreview(BuildContext context) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject == null || _previewPosition == null) {
      return const SizedBox.shrink();
    }

    final box = renderObject as RenderBox;
    final Offset localPosition = box.globalToLocal(_dragPosition!);

    // Calculate horizontal position, ensuring it stays within screen bounds
    final double screenWidth = MediaQuery.of(context).size.width;
    const double previewWidth = 160.0; // Increased from 120
    const double previewHeight = 90.0; // Increased from 80
    const double previewPadding = 10.0;

    double leftPosition = localPosition.dx - (previewWidth / 2);

    // Keep preview within screen bounds
    if (leftPosition < previewPadding) {
      leftPosition = previewPadding;
    } else if (leftPosition + previewWidth > screenWidth - previewPadding) {
      leftPosition = screenWidth - previewWidth - previewPadding;
    }

    // Position above the progress bar
    const double bottomPosition = 60.0;

    return Positioned(
      left: leftPosition,
      bottom: bottomPosition,
      child: _ThumbnailPreviewWidget(
        controller: controller!,
        position: _previewPosition!,
        width: previewWidth,
        height: previewHeight,
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter(this.value, this.colors, this._betterPlayerController);

  VideoPlayerValue value;
  BetterPlayerProgressColors colors;
  BetterPlayerController _betterPlayerController;

  @override
  bool shouldRepaint(CustomPainter painter) {
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    double height = _betterPlayerController.isFullScreen ? 4.0 : 2.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(Offset(0.0, size.height / 2), Offset(size.width, size.height / 2 + height)),
        const Radius.circular(4.0),
      ),
      colors.backgroundPaint,
    );
    if (!value.initialized) {
      return;
    }
    double playedPartPercent = value.position.inMilliseconds / value.duration!.inMilliseconds;
    if (playedPartPercent.isNaN) {
      playedPartPercent = 0;
    }
    final double playedPart = playedPartPercent > 1 ? size.width : playedPartPercent * size.width;
    for (final DurationRange range in value.buffered) {
      double start = range.startFraction(value.duration!) * size.width;
      if (start.isNaN) {
        start = 0;
      }
      double end = range.endFraction(value.duration!) * size.width;
      if (end.isNaN) {
        end = 0;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(Offset(start, size.height / 2), Offset(end, size.height / 2 + height)),
          const Radius.circular(4.0),
        ),
        colors.bufferedPaint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(Offset(0.0, size.height / 2), Offset(playedPart, size.height / 2 + height)),
        const Radius.circular(4.0),
      ),
      colors.playedPaint,
    );
    canvas.drawCircle(Offset(playedPart, size.height / 2 + height / 2), height * 3, colors.handlePaint);
  }
}

/// Widget that displays a thumbnail preview of the video at a specific position
class _ThumbnailPreviewWidget extends StatelessWidget {
  const _ThumbnailPreviewWidget({
    required this.controller,
    required this.position,
    required this.width,
    required this.height,
  });

  final VideoPlayerController controller;
  final Duration position;
  final double width;
  final double height;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  /// Check if position is buffered
  bool _isBuffered() {
    for (final DurationRange range in controller.value.buffered) {
      if (position >= range.start && position <= range.end) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bool isBuffered = _isBuffered();

    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Video frame preview
          SizedBox(
            width: width,
            height: height,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6.0)),
              child: Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    // Video frame - use contain to show full frame without cropping
                    Center(
                      child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller)),
                    ),
                    // Loading overlay for unbuffered content
                    if (!isBuffered)
                      Container(
                        color: Colors.black.withOpacity(0.7),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.8)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Loading...',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
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
          ),
          // Timestamp
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6.0)),
            ),
            child: Text(
              _formatDuration(position),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
