import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// How long the overlay takes to fade in or out.
const Duration betterPlayerMotionDuration = Duration(milliseconds: 160);

/// The player's own colours. It sits over video, which is dark whatever the
/// app's theme, so these stay fixed: white ink, black glass, and panels a
/// step off black. The accent is kept to the timeline.
abstract final class BetterPlayerColors {
  /// A control at rest: black at 45%.
  static const Color idle = Color(0x73000000);

  /// A control under the finger: near-white, with a black icon.
  static const Color pressed = Color(0xF2FFFFFF);

  /// Sheets and panels opened from the player.
  static const Color panel = Color(0xFF161616);

  /// A tile or a selected row inside a panel.
  static const Color panelRaised = Color(0xFF262626);

  static const Color foreground = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFFD4D4D4);
  static const Color muted = Color(0xFFA3A3A3);
  static const Color hairline = Color(0x1FFFFFFF);
}

/// The panels' theme: dark, with the host app's accent kept as `primary` for
/// progress, whatever mode the app itself is in.
ThemeData betterPlayerPanelTheme(ThemeData inherited) {
  final accent = inherited.colorScheme.primary;
  final base = ThemeData(
    useMaterial3: inherited.useMaterial3,
    brightness: Brightness.dark,
    fontFamily: inherited.textTheme.bodyMedium?.fontFamily,
  );
  final scheme = ColorScheme.dark(
    primary: accent,
    onPrimary: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black,
    surface: BetterPlayerColors.panel,
    onSurface: BetterPlayerColors.foreground,
    onSurfaceVariant: BetterPlayerColors.muted,
    surfaceContainerHigh: BetterPlayerColors.panel,
    surfaceContainerHighest: BetterPlayerColors.panelRaised,
    outlineVariant: BetterPlayerColors.hairline,
    error: inherited.colorScheme.error,
  );
  const white = BetterPlayerColors.foreground;
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  const buttonText = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
  return base.copyWith(
    colorScheme: scheme,
    canvasColor: BetterPlayerColors.panel,
    scaffoldBackgroundColor: BetterPlayerColors.panel,
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    iconTheme: const IconThemeData(color: white),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: white,
      linearTrackColor: Colors.white24,
      circularTrackColor: Colors.transparent,
    ),
    textSelectionTheme: inherited.textSelectionTheme,
    // White pills with black text, as Netflix's; never the accent.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BetterPlayerColors.pressed,
        foregroundColor: Colors.black,
        disabledBackgroundColor: Colors.white12,
        disabledForegroundColor: Colors.white38,
        minimumSize: const Size(0, 44),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BetterPlayerColors.pressed,
        foregroundColor: Colors.black,
        minimumSize: const Size(0, 44),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: white,
        side: const BorderSide(color: Colors.white38),
        minimumSize: const Size(0, 44),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: white, textStyle: buttonText),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: white)),
    sliderTheme: const SliderThemeData(
      activeTrackColor: white,
      inactiveTrackColor: Colors.white24,
      thumbColor: white,
      overlayColor: Color(0x1FFFFFFF),
      activeTickMarkColor: Colors.transparent,
      inactiveTickMarkColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.black : Colors.white70,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? white : Colors.white24,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? white : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.black),
      side: const BorderSide(color: Colors.white54, width: 1.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x1AFFFFFF),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: BetterPlayerColors.muted),
      prefixIconColor: BetterPlayerColors.muted,
      suffixIconColor: BetterPlayerColors.muted,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white54),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF2B2B2B),
      contentTextStyle: TextStyle(color: white, fontSize: 14),
      actionTextColor: white,
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: BetterPlayerColors.panel),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: BetterPlayerColors.panel,
      modalBackgroundColor: BetterPlayerColors.panel,
    ),
    dividerTheme: const DividerThemeData(color: BetterPlayerColors.hairline, space: 1),
    listTileTheme: const ListTileThemeData(iconColor: BetterPlayerColors.muted, textColor: white),
  );
}

/// A control over the picture: a black-glass circle with a white icon that
/// turns white, with a black icon, while it is pressed. With [showLabel] it
/// is a pill naming itself beside the icon, as the labelled actions under
/// the timeline are.
class BetterPlayerControlButton extends StatefulWidget {
  const BetterPlayerControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor = Colors.white,
    this.selected = false,
    this.backgroundColor,
    this.size = 44,
    this.iconSize = 22,
    this.showLabel = false,
    this.labelStyle,
    this.glyphBuilder,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color iconColor;

  /// Shown as though pressed, for a state that is on (the lock).
  final bool selected;

  /// The fill at rest; [BetterPlayerColors.idle] unless given.
  final Color? backgroundColor;
  final double size;
  final double iconSize;
  final bool showLabel;
  final TextStyle? labelStyle;

  /// Draws the icon in the colour it is given, for a glyph an [IconData]
  /// can't carry (the seconds inside a skip arrow).
  final Widget Function(Color color)? glyphBuilder;

  @override
  State<BetterPlayerControlButton> createState() => _BetterPlayerControlButtonState();
}

class _BetterPlayerControlButtonState extends State<BetterPlayerControlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final active = enabled && (_pressed || widget.selected);
    final background = active ? BetterPlayerColors.pressed : widget.backgroundColor ?? BetterPlayerColors.idle;
    final foreground = active ? Colors.black : widget.iconColor;
    final glyph = widget.glyphBuilder?.call(foreground) ?? Icon(widget.icon, size: widget.iconSize, color: foreground);
    final radius = BorderRadius.circular(widget.size / 2);
    Widget button = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      height: widget.size,
      constraints: BoxConstraints(minWidth: widget.size),
      decoration: BoxDecoration(color: background, borderRadius: radius),
      child: Material(
        type: MaterialType.transparency,
        child: InkResponse(
          onTap: widget.onPressed,
          onHighlightChanged: (value) {
            if (mounted && value != _pressed) setState(() => _pressed = value);
          },
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          borderRadius: radius,
          customBorder: RoundedRectangleBorder(borderRadius: radius),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.showLabel ? 14 : 0),
            child: widget.showLabel
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      glyph,
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (widget.labelStyle ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
                              .copyWith(color: foreground),
                        ),
                      ),
                    ],
                  )
                : Center(child: glyph),
          ),
        ),
      ),
    );
    if (!enabled) button = Opacity(opacity: .4, child: button);
    if (!widget.showLabel) button = Tooltip(message: widget.label, child: button);
    return Semantics(
      button: true,
      label: widget.label,
      enabled: enabled,
      selected: widget.selected,
      child: button,
    );
  }
}

/// A circular arrow with the seconds it skips written inside it.
class BetterPlayerSkipGlyph extends StatelessWidget {
  const BetterPlayerSkipGlyph({
    required this.forward,
    required this.seconds,
    required this.color,
    this.size = 30,
    super.key,
  });

  final bool forward;
  final int seconds;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            forward ? PhosphorIconsRegular.arrowClockwise : PhosphorIconsRegular.arrowCounterClockwise,
            size: size,
            color: color,
          ),
          Padding(
            padding: EdgeInsets.only(top: size * .06),
            child: Text(
              '$seconds',
              style: TextStyle(
                color: color,
                fontSize: size * .3,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "LIVE", with a red dot, where a timeline would otherwise be.
class BetterPlayerLiveBadge extends StatelessWidget {
  const BetterPlayerLiveBadge({required this.label, this.dotColor = const Color(0xFFE50914), super.key});

  final String label;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dark panel rising from the bottom, for everything the player opens:
/// a title, a close button and whatever list it holds.
class BetterPlayerModalSheet extends StatelessWidget {
  const BetterPlayerModalSheet({required this.title, required this.child, this.subtitle, this.closeLabel, super.key});

  final String title;
  final String? subtitle;
  final String? closeLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: height * .9),
          child: Material(
            color: BetterPlayerColors.panel,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
                ),
                BetterPlayerPanelHeader(title: title, subtitle: subtitle, closeLabel: closeLabel),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A panel's heading: its title, a muted line under it, and a close button
/// at the end.
class BetterPlayerPanelHeader extends StatelessWidget {
  const BetterPlayerPanelHeader({required this.title, this.subtitle, this.closeLabel, super.key});

  final String title;
  final String? subtitle;
  final String? closeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (subtitle?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: BetterPlayerColors.muted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: closeLabel ?? MaterialLocalizations.of(context).closeButtonTooltip,
            color: Colors.white,
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(PhosphorIcons.x()),
          ),
        ],
      ),
    );
  }
}

/// A plain icon, muted, in a faint circle: for errors and empty lists.
class BetterPlayerIconSurface extends StatelessWidget {
  const BetterPlayerIconSurface({required this.icon, this.color, super.key});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(color: Color(0x1AFFFFFF), shape: BoxShape.circle),
      child: Icon(icon, color: color ?? BetterPlayerColors.secondary),
    );
  }
}

/// One option in a panel: a check at the start on the chosen one, the name,
/// and a muted detail. An async [onTap] shows a spinner until it is done.
class BetterPlayerSelectionTile extends StatefulWidget {
  const BetterPlayerSelectionTile({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.enabled = true,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final FutureOr<void> Function()? onTap;
  final Widget? trailing;

  @override
  State<BetterPlayerSelectionTile> createState() => _BetterPlayerSelectionTileState();
}

class _BetterPlayerSelectionTileState extends State<BetterPlayerSelectionTile> {
  bool _loading = false;

  Future<void> _handleTap() async {
    final onTap = widget.onTap;
    if (_loading || onTap == null) return;
    setState(() => _loading = true);
    try {
      await onTap();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = !widget.enabled
        ? Colors.white38
        : widget.selected
        ? Colors.white
        : BetterPlayerColors.secondary;
    return Semantics(
      selected: widget.selected,
      button: true,
      child: Material(
        color: widget.selected ? const Color(0x14FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.enabled && !_loading ? _handleTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: widget.selected
                        ? Icon(PhosphorIcons.check(PhosphorIconsStyle.bold), size: 20, color: Colors.white)
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 15,
                            fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        if (widget.subtitle?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: BetterPlayerColors.muted, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_loading)
                    const SizedBox.square(
                      key: Key('better_player_selection_progress'),
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else if (widget.trailing != null)
                    widget.trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row in the player's More panel: a muted icon, the setting's name, its
/// current value and a chevron.
class BetterPlayerMenuRow extends StatelessWidget {
  const BetterPlayerMenuRow({required this.icon, required this.title, required this.onTap, this.value, super.key});

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            child: Row(
              children: [
                Icon(icon, size: 22, color: BetterPlayerColors.muted),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                if (value?.isNotEmpty == true) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: BetterPlayerColors.muted, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(PhosphorIcons.caretRight(), size: 18, color: BetterPlayerColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A heading over one column of a panel ("Audio", "Subtitles").
class BetterPlayerPanelSectionTitle extends StatelessWidget {
  const BetterPlayerPanelSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class BetterPlayerEmptyState extends StatelessWidget {
  const BetterPlayerEmptyState({required this.icon, required this.title, this.message, super.key});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BetterPlayerIconSurface(icon: icon),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: BetterPlayerColors.muted, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

/// Speeds as stops along a line, the chosen one a larger white dot. Reads
/// left to right in every language, slowest first.
class BetterPlayerSpeedSelector extends StatelessWidget {
  const BetterPlayerSpeedSelector({
    required this.speeds,
    required this.selected,
    required this.onSelected,
    required this.normalLabel,
    super.key,
  });

  final List<double> speeds;
  final double selected;
  final ValueChanged<double> onSelected;
  final String normalLabel;

  static String format(double speed) {
    final text = speed.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '${text}x';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset = constraints.maxWidth / (speeds.length * 2);
          return SizedBox(
            height: 76,
            child: Stack(
              children: [
                Positioned(
                  left: inset,
                  right: inset,
                  top: 21,
                  height: 2,
                  child: const ColoredBox(color: Colors.white24),
                ),
                Row(
                  children: [
                    for (final speed in speeds)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: speed == selected,
                          label: speed == 1 ? '${format(speed)} $normalLabel' : format(speed),
                          excludeSemantics: true,
                          child: InkWell(
                            key: ValueKey('better_player_speed_${format(speed)}'),
                            onTap: () => onSelected(speed),
                            borderRadius: BorderRadius.circular(8),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 44,
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      width: speed == selected ? 22 : 10,
                                      height: speed == selected ? 22 : 10,
                                      decoration: BoxDecoration(
                                        color: speed == selected ? Colors.white : Colors.white54,
                                        shape: BoxShape.circle,
                                        border: speed == selected
                                            ? Border.all(color: const Color(0x66FFFFFF), width: 5)
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  speed == 1 ? '${format(speed)} ($normalLabel)' : format(speed),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: speed == selected ? Colors.white : BetterPlayerColors.muted,
                                    fontSize: 13,
                                    fontWeight: speed == selected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// What a swipe or double tap just did: volume, brightness, or a seek.
class BetterPlayerGesturePill extends StatelessWidget {
  const BetterPlayerGesturePill({required this.icon, required this.label, this.value, super.key});

  final IconData icon;
  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(color: const Color(0xA6000000), borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    value: value!.clamp(0, 1),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
