import 'dart:async';

import 'package:better_player_plus/better_player.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';

/// The phone timeline: a thin track whose played part is the one touch of
/// the accent. Dragging thickens it and shows the time the handle is on in a
/// bubble above it; the seek happens once, when the finger lifts, so a slow
/// stream isn't asked for every frame on the way. A tap jumps straight
/// there.
///
/// It always runs left to right, as a timeline does in every language.
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
    this.timeStyle,
    super.key,
  }) : colors = colors ?? BetterPlayerProgressColors();

  final VideoPlayerController? controller;
  final BetterPlayerController? betterPlayerController;
  final BetterPlayerProgressColors colors;
  final Function()? onDragStart;
  final Function()? onDragEnd;
  final Function()? onDragUpdate;
  final Function()? onTapDown;

  /// Whether dragging shows the time bubble.
  final bool showThumbnailPreview;
  final TextStyle? timeStyle;

  @override
  State<BetterPlayerMaterialVideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<BetterPlayerMaterialVideoProgressBar> {
  VideoPlayerController? _listened;

  /// Where the handle is while a finger holds it, as a fraction.
  double? _dragFraction;

  /// A seek just sent, shown until the player reports it, so the handle
  /// doesn't jump back for a frame.
  Duration? _pendingSeek;
  Timer? _pendingSeekTimer;

  VideoPlayerController? get controller => widget.controller;

  bool get _dragEnabled =>
      widget.betterPlayerController?.betterPlayerConfiguration.controlsConfiguration.enableProgressBarDrag ?? true;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(BetterPlayerMaterialVideoProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) _listen();
  }

  void _listen() {
    _listened?.removeListener(_onValue);
    _listened = controller;
    _listened?.addListener(_onValue);
  }

  void _onValue() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _listened?.removeListener(_onValue);
    _pendingSeekTimer?.cancel();
    super.dispose();
  }

  Duration? get _duration {
    final value = controller?.value;
    if (value == null || !value.initialized) return null;
    final duration = value.duration;
    return duration == null || duration <= Duration.zero ? null : duration;
  }

  double _fractionAt(Offset localPosition, double width) => width <= 0 ? 0 : (localPosition.dx / width).clamp(0.0, 1.0);

  Future<void> _seekToFraction(double fraction) async {
    final duration = _duration;
    if (duration == null) return;
    final target = duration * fraction;
    _pendingSeekTimer?.cancel();
    setState(() => _pendingSeek = target);
    _pendingSeekTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _pendingSeek = null);
    });
    await widget.betterPlayerController?.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final value = controller?.value;
    final duration = _duration;
    final fullscreen = widget.betterPlayerController?.isFullScreen ?? false;
    final dragging = _dragFraction != null;
    final position = _pendingSeek ?? value?.position ?? Duration.zero;
    final played = duration == null
        ? 0.0
        : dragging
        ? _dragFraction!
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final buffered = <(double, double)>[
      if (duration != null)
        for (final range in value?.buffered ?? const <DurationRange>[])
          (
            (range.start.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0),
            (range.end.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0),
          ),
    ];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    if (duration == null || !_dragEnabled) return;
                    setState(() => _dragFraction = _fractionAt(details.localPosition, width));
                    widget.onDragStart?.call();
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_dragFraction == null) return;
                    setState(() => _dragFraction = _fractionAt(details.localPosition, width));
                    widget.onDragUpdate?.call();
                  },
                  onHorizontalDragEnd: (_) {
                    final fraction = _dragFraction;
                    if (fraction == null) return;
                    setState(() => _dragFraction = null);
                    unawaited(_seekToFraction(fraction));
                    widget.onDragEnd?.call();
                  },
                  onHorizontalDragCancel: () {
                    if (_dragFraction == null) return;
                    setState(() => _dragFraction = null);
                    widget.onDragEnd?.call();
                  },
                  onTapDown: (details) {
                    if (duration == null || !_dragEnabled) return;
                    unawaited(_seekToFraction(_fractionAt(details.localPosition, width)));
                    widget.onTapDown?.call();
                  },
                  child: CustomPaint(
                    painter: _ProgressBarPainter(
                      played: played,
                      buffered: buffered,
                      colors: widget.colors,
                      trackHeight: dragging ? 6 : (fullscreen ? 4 : 3),
                      handleRadius: duration == null ? 0 : (dragging ? 10 : 7),
                    ),
                  ),
                ),
              ),
              if (dragging && widget.showThumbnailPreview && duration != null)
                _TimeBubble(
                  label: BetterPlayerUtils.formatDuration(duration * _dragFraction!),
                  centerX: width * _dragFraction!,
                  width: width,
                  style: widget.timeStyle,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The time under the handle, floating above it while it is dragged.
class _TimeBubble extends StatelessWidget {
  const _TimeBubble({required this.label, required this.centerX, required this.width, this.style});

  static const double _bubbleWidth = 76;

  final String label;
  final double centerX;
  final double width;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final left = (centerX - _bubbleWidth / 2).clamp(0.0, (width - _bubbleWidth).clamp(0.0, double.infinity));
    return Positioned(
      left: left,
      bottom: 30,
      width: _bubbleWidth,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE6000000),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: (style ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)).copyWith(
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter({
    required this.played,
    required this.buffered,
    required this.colors,
    required this.trackHeight,
    required this.handleRadius,
  });

  final double played;
  final List<(double, double)> buffered;
  final BetterPlayerProgressColors colors;
  final double trackHeight;
  final double handleRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - trackHeight) / 2;
    final radius = Radius.circular(trackHeight / 2);
    RRect bar(double from, double to) =>
        RRect.fromRectAndRadius(Rect.fromLTRB(size.width * from, top, size.width * to, top + trackHeight), radius);

    canvas.drawRRect(bar(0, 1), colors.backgroundPaint);
    for (final (start, end) in buffered) {
      if (end > start) canvas.drawRRect(bar(start, end), colors.bufferedPaint);
    }
    if (played > 0) canvas.drawRRect(bar(0, played), colors.playedPaint);
    if (handleRadius > 0) {
      canvas.drawCircle(Offset(size.width * played, size.height / 2), handleRadius, colors.handlePaint);
    }
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) =>
      old.played != played ||
      old.trackHeight != trackHeight ||
      old.handleRadius != handleRadius ||
      old.colors != colors ||
      old.buffered.length != buffered.length ||
      !_sameRanges(old.buffered, buffered);

  static bool _sameRanges(List<(double, double)> a, List<(double, double)> b) {
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
