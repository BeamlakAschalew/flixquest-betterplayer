// ignore_for_file: cascade_invocations

import 'dart:async';
import 'package:better_player_plus/src/controls/better_player_progress_colors.dart';
import 'package:better_player_plus/src/core/better_player_controller.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class BetterPlayerCupertinoVideoProgressBar extends StatefulWidget {
  BetterPlayerCupertinoVideoProgressBar(
    this.controller,
    this.betterPlayerController, {
    BetterPlayerProgressColors? colors,
    this.onDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onTapDown,
    this.showThumbnailPreview = true,
    super.key,
  }) : colors = colors ?? BetterPlayerProgressColors();

  final VideoPlayerController? controller;
  final BetterPlayerController? betterPlayerController;
  final BetterPlayerProgressColors colors;
  final void Function()? onDragStart;
  final void Function()? onDragEnd;
  final void Function()? onDragUpdate;
  final void Function()? onTapDown;
  final bool showThumbnailPreview;

  @override
  State<BetterPlayerCupertinoVideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<BetterPlayerCupertinoVideoProgressBar> {
  _VideoProgressBarState() {
    listener = () {
      if (mounted) {
        setState(() {});
      }
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
    final bool enableProgressBarDrag = betterPlayerController!.betterPlayerControlsConfiguration.enableProgressBarDrag;
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
              width: MediaQuery.sizeOf(context).width,
              height: MediaQuery.sizeOf(context).height,
              color: Colors.transparent,
              child: CustomPaint(painter: _ProgressBarPainter(_getValue(), widget.colors)),
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

  Future<void> seekToRelativePosition(Offset globalPosition) async {
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
  _ProgressBarPainter(this.value, this.colors);

  VideoPlayerValue value;
  BetterPlayerProgressColors colors;

  @override
  bool shouldRepaint(CustomPainter painter) => true;

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 5.0;
    const handleHeight = 6.0;
    final baseOffset = size.height / 2 - barHeight / 2.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(Offset(0, baseOffset), Offset(size.width, baseOffset + barHeight)),
        const Radius.circular(4),
      ),
      colors.backgroundPaint,
    );
    if (!value.initialized) {
      return;
    }
    final double playedPartPercent = value.position.inMilliseconds / value.duration!.inMilliseconds;
    final double playedPart = playedPartPercent > 1 ? size.width : playedPartPercent * size.width;
    for (final DurationRange range in value.buffered) {
      final double start = range.startFraction(value.duration!) * size.width;
      final double end = range.endFraction(value.duration!) * size.width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(Offset(start, baseOffset), Offset(end, baseOffset + barHeight)),
          const Radius.circular(4),
        ),
        colors.bufferedPaint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(Offset(0, baseOffset), Offset(playedPart, baseOffset + barHeight)),
        const Radius.circular(4),
      ),
      colors.playedPaint,
    );

    final shadowPath = Path()
      ..addOval(Rect.fromCircle(center: Offset(playedPart, baseOffset + barHeight / 2), radius: handleHeight));

    canvas.drawShadow(shadowPath, Colors.black, 0.2, false);
    canvas.drawCircle(Offset(playedPart, baseOffset + barHeight / 2), handleHeight, colors.handlePaint);
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
                        color: CupertinoColors.black.withOpacity(0.7),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CupertinoActivityIndicator(color: CupertinoColors.white.withOpacity(0.8)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Loading...',
                                style: TextStyle(
                                  color: CupertinoColors.white.withOpacity(0.8),
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
