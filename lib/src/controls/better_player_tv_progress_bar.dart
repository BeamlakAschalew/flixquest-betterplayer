import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BetterPlayerTvProgressBar extends StatefulWidget {
  const BetterPlayerTvProgressBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    required this.onEditingChanged,
    this.seekStep = const Duration(seconds: 10),
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
  final Duration seekStep;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;

  @override
  State<BetterPlayerTvProgressBar> createState() => _BetterPlayerTvProgressBarState();
}

class _BetterPlayerTvProgressBarState extends State<BetterPlayerTvProgressBar> {
  bool _focused = false;
  Duration? _preview;

  Duration get _effectivePosition => _preview ?? widget.position;

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _adjust(-widget.seekStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _adjust(widget.seekStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      final preview = _preview;
      if (preview != null) {
        widget.onSeek(preview);
        setState(() => _preview = null);
        widget.onEditingChanged(false);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      if (_preview != null) {
        setState(() => _preview = null);
        widget.onEditingChanged(false);
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
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = math.max(1, widget.duration.inMilliseconds);
    final played = (_effectivePosition.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final buffered = (widget.buffered.inMilliseconds / durationMs).clamp(0.0, 1.0);

    return Semantics(
      slider: true,
      label: 'Playback position',
      value: '${_format(_effectivePosition)} of ${_format(widget.duration)}',
      child: Focus(
        onKeyEvent: _handleKey,
        onFocusChange: (focused) {
          setState(() {
            _focused = focused;
            if (!focused) _preview = null;
          });
          if (!focused) widget.onEditingChanged(false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: _focused ? Colors.black54 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _focused ? widget.playedColor : Colors.transparent, width: 3),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 74,
                child: Text(
                  _format(_effectivePosition),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
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
                        Align(
                          alignment: Alignment(played * 2 - 1, 0),
                          child: Container(
                            width: _focused ? 14 : 8,
                            height: _focused ? 14 : 8,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: widget.playedColor, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 74,
                child: Text(
                  _format(widget.duration),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
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
