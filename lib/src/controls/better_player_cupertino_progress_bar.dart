// ignore_for_file: cascade_invocations

import 'dart:async';
import 'package:better_player_plus/src/controls/better_player_progress_colors.dart';
import 'package:better_player_plus/src/core/better_player_controller.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
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

  @override
  void initState() {
    super.initState();
    controller!.addListener(listener);
  }

  @override
  void deactivate() {
    controller!.removeListener(listener);
    _cancelUpdateBlockTimer();
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

  Widget _buildThumbnailPreview(BuildContext context) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject == null || _previewPosition == null) {
      return const SizedBox.shrink();
    }

    final box = renderObject as RenderBox;
    final Offset localPosition = box.globalToLocal(_dragPosition!);

    // Calculate horizontal position, ensuring it stays within screen bounds
    final double screenWidth = MediaQuery.of(context).size.width;
    const double previewWidth = 120.0;
    const double previewHeight = 80.0;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
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
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6.0)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6.0)),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size?.width ?? 1.0,
                  height: controller.value.size?.height ?? 1.0,
                  child: VideoPlayer(controller),
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
