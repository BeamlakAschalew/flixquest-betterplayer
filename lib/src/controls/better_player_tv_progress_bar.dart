import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The TV timeline: a thin track that thickens under focus, where Left and
/// Right scrub a preview of the new position and the seek happens once the
/// remote pauses, or at once with OK.
class BetterPlayerTvProgressBar extends StatefulWidget {
  const BetterPlayerTvProgressBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    required this.onEditingChanged,
    this.focusNode,
    this.seekStep = const Duration(seconds: 10),
    this.commitDelay = const Duration(milliseconds: 900),
    this.playedColor = Colors.deepOrange,
    this.bufferedColor = Colors.white54,
    this.backgroundColor = Colors.white24,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool> onEditingChanged;
  final FocusNode? focusNode;
  final Duration seekStep;

  /// How long the remote must rest before a scrub is applied.
  final Duration commitDelay;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;

  @override
  State<BetterPlayerTvProgressBar> createState() => BetterPlayerTvProgressBarState();
}

class BetterPlayerTvProgressBarState extends State<BetterPlayerTvProgressBar> {
  bool _focused = false;
  Duration? _preview;
  Timer? _commitTimer;

  Duration get _effectivePosition => _preview ?? widget.position;

  /// Moves the preview by [steps] seek steps, as that many Right presses (or
  /// Left, for a negative count) would.
  void nudge(int steps) => _adjust(widget.seekStep * steps);

  @override
  void dispose() {
    _commitTimer?.cancel();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      nudge(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      nudge(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      _commit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      if (_preview != null) {
        _cancel();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _adjust(Duration delta) {
    final maxMs = math.max(0, widget.duration.inMilliseconds);
    final nextMs = (_effectivePosition + delta).inMilliseconds.clamp(0, maxMs);
    if (_preview == null) widget.onEditingChanged(true);
    setState(() => _preview = Duration(milliseconds: nextMs));
    _commitTimer?.cancel();
    _commitTimer = Timer(widget.commitDelay, _commit);
  }

  void _commit() {
    _commitTimer?.cancel();
    final preview = _preview;
    if (preview == null || !mounted) return;
    widget.onSeek(preview);
    setState(() => _preview = null);
    widget.onEditingChanged(false);
  }

  void _cancel() {
    _commitTimer?.cancel();
    setState(() => _preview = null);
    widget.onEditingChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = math.max(1, widget.duration.inMilliseconds);
    final played = (_effectivePosition.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final buffered = (widget.buffered.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final remaining = widget.duration - _effectivePosition;
    final preview = _preview;
    const timeStyle = TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );

    return Semantics(
      slider: true,
      label: 'Playback position',
      value: '${_format(_effectivePosition)} of ${_format(widget.duration)}',
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: _handleKey,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          // Leaving the timeline applies what was scrubbed, as pausing would.
          if (!focused) _commit();
        },
        child: SizedBox(
          height: 44,
          child: Row(
            children: <Widget>[
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final knob = _focused ? 16.0 : 10.0;
                    return Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: <Widget>[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          height: _focused ? 6 : 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                ColoredBox(color: widget.backgroundColor),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: buffered,
                                  child: ColoredBox(color: widget.bufferedColor),
                                ),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: played,
                                  child: ColoredBox(color: widget.playedColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: width * played - knob / 2,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: knob,
                            height: knob,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: _focused
                                  ? const <BoxShadow>[BoxShadow(color: Color(0x66ffffff), blurRadius: 10)]
                                  : null,
                            ),
                          ),
                        ),
                        // Where a scrub will land, over the knob. There are
                        // no thumbnail tracks to show, so the time stands in.
                        if (preview != null)
                          Positioned(
                            left: (width * played - 40).clamp(0.0, math.max(0.0, width - 80)),
                            bottom: 16,
                            child: Container(
                              width: 80,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xf2ffffff),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                _format(preview),
                                textAlign: TextAlign.center,
                                style: timeStyle.copyWith(color: Colors.black, fontSize: 17),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 18),
              // What is left, counted down, as Netflix shows it.
              Text('-${_format(remaining.isNegative ? Duration.zero : remaining)}', style: timeStyle),
            ],
          ),
        ),
      ),
    );
  }

  String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
