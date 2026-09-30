import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// How long the overlay takes to fade in or out.
const Duration betterPlayerMotionDuration = Duration(milliseconds: 160);

/// The colours of things drawn over the video: controls, badges, the
/// gesture pill. The picture is dark whatever the app's theme, so these stay
/// fixed: white ink and black glass. The accent is kept to the timeline.
abstract final class BetterPlayerColors {
  /// A control at rest: black at 45%.
  static const Color idle = Color(0x73000000);

  /// A control under the finger: near-white, with a black icon.
  static const Color pressed = Color(0xF2FFFFFF);

  /// Panels over the picture in the dark modes.
  static const Color panel = Color(0xFF161616);
  static const Color panelRaised = Color(0xFF262626);

  static const Color foreground = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFFD4D4D4);
  static const Color muted = Color(0xFFA3A3A3);
  static const Color hairline = Color(0x1FFFFFFF);
}

/// The colours of the panels the player opens (sheets, lists, menus). They
/// follow the app: near-white in Light, a step off black in the dark modes.
@immutable
class BetterPlayerPanelColors extends ThemeExtension<BetterPlayerPanelColors> {
  const BetterPlayerPanelColors({
    required this.page,
    required this.panel,
    required this.raised,
    required this.foreground,
    required this.secondary,
    required this.muted,
    required this.hairline,
    required this.selectedFill,
    required this.pill,
    required this.onPill,
    required this.track,
  });

  static const BetterPlayerPanelColors dark = BetterPlayerPanelColors(
    page: Color(0xFF000000),
    panel: BetterPlayerColors.panel,
    raised: BetterPlayerColors.panelRaised,
    foreground: BetterPlayerColors.foreground,
    secondary: BetterPlayerColors.secondary,
    muted: BetterPlayerColors.muted,
    hairline: BetterPlayerColors.hairline,
    selectedFill: Color(0x14FFFFFF),
    pill: BetterPlayerColors.pressed,
    onPill: Color(0xFF000000),
    track: Color(0x3DFFFFFF),
  );

  /// Light panels on [page], the app's own page colour.
  factory BetterPlayerPanelColors.light(Color page) {
    const ink = Color(0xFF141516);
    Color lift(double alpha) => Color.alphaBlend(ink.withValues(alpha: alpha), page);
    return BetterPlayerPanelColors(
      page: page,
      panel: page,
      raised: lift(.07),
      foreground: ink,
      secondary: const Color(0xFF2F3134),
      muted: const Color(0xFF5C5F63),
      hairline: ink.withValues(alpha: .12),
      selectedFill: ink.withValues(alpha: .06),
      pill: ink.withValues(alpha: .95),
      onPill: const Color(0xFFFFFFFF),
      track: ink.withValues(alpha: .16),
    );
  }

  /// The screen behind a portrait player, around the video.
  final Color page;

  /// A sheet's background.
  final Color panel;

  /// Tiles and placeholders on a panel.
  final Color raised;
  final Color foreground;
  final Color secondary;
  final Color muted;
  final Color hairline;

  /// Behind the chosen row.
  final Color selectedFill;

  /// The main button, and what is written on it.
  final Color pill;
  final Color onPill;

  /// The unfilled part of a slider or bar.
  final Color track;

  bool get isLight => ThemeData.estimateBrightnessForColor(panel) == Brightness.light;

  /// The panel colours in effect; the dark ones anywhere no panel theme was
  /// set, which is over the video.
  static BetterPlayerPanelColors of(BuildContext context) =>
      Theme.of(context).extension<BetterPlayerPanelColors>() ?? dark;

  @override
  BetterPlayerPanelColors copyWith() => this;

  @override
  BetterPlayerPanelColors lerp(BetterPlayerPanelColors? other, double t) {
    if (other == null) return this;
    return BetterPlayerPanelColors(
      page: Color.lerp(page, other.page, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t)!,
      pill: Color.lerp(pill, other.pill, t)!,
      onPill: Color.lerp(onPill, other.onPill, t)!,
      track: Color.lerp(track, other.track, t)!,
    );
  }
}

/// The colours of the TV player's panels (menus and prompts opened over the
/// picture). They follow the app the way its own TV screens do, built from
/// the theme's page colour: a panel a shade off the page, so near-black in
/// Lights Out and near-white in Light, and focus filled with the page's ink.
@immutable
class BetterPlayerTvPanelColors {
  const BetterPlayerTvPanelColors._({
    required this.dark,
    required this.panel,
    required this.foreground,
    required this.muted,
    required this.disabled,
    required this.idleFill,
    required this.track,
    required this.focusFill,
    required this.onFocus,
    required this.onFocusMuted,
    required this.onFocusTrack,
  });

  factory BetterPlayerTvPanelColors.fromTheme(ThemeData theme) {
    final dark = theme.colorScheme.brightness == Brightness.dark;
    final page = theme.scaffoldBackgroundColor;
    final ink = dark ? const Color(0xfff7f7f7) : const Color(0xff141516);
    return BetterPlayerTvPanelColors._(
      dark: dark,
      panel: Color.alphaBlend(ink.withValues(alpha: dark ? .045 : .035), page).withValues(alpha: .96),
      foreground: ink,
      muted: dark ? const Color(0xffa7a8a8) : const Color(0xff5c5f63),
      disabled: ink.withValues(alpha: .38),
      idleFill: ink.withValues(alpha: .14),
      track: ink.withValues(alpha: .24),
      focusFill: ink.withValues(alpha: .95),
      onFocus: dark ? Colors.black : Colors.white,
      onFocusMuted: dark ? Colors.black54 : Colors.white70,
      onFocusTrack: dark ? Colors.black12 : Colors.white24,
    );
  }

  static final Expando<BetterPlayerTvPanelColors> _cache = Expando<BetterPlayerTvPanelColors>(
    'BetterPlayerTvPanelColors',
  );

  /// The colours for the theme in effect at [context], built once per theme.
  static BetterPlayerTvPanelColors of(BuildContext context) {
    final theme = Theme.of(context);
    return _cache[theme] ??= BetterPlayerTvPanelColors.fromTheme(theme);
  }

  final bool dark;

  /// A panel's background.
  final Color panel;

  /// Titles, labels and icons.
  final Color foreground;
  final Color muted;
  final Color disabled;

  /// A control at rest.
  final Color idleFill;

  /// The unfilled part of a bar.
  final Color track;

  /// A focused control: white on a dark page, near-black on a light one,
  /// with [onFocus] for what is on it.
  final Color focusFill;
  final Color onFocus;
  final Color onFocusMuted;
  final Color onFocusTrack;
}

/// The panels' theme. It follows the app's mode (light panels in Light,
/// dark ones otherwise) unless [dark] asks for the dark panels whatever the
/// mode, for anything drawn over the video. The app's accent stays `primary`
/// for progress; buttons are ink pills, never the accent.
ThemeData betterPlayerPanelTheme(ThemeData inherited, {bool dark = false}) {
  final accent = inherited.colorScheme.primary;
  final light = !dark && inherited.colorScheme.brightness == Brightness.light;
  final colors = light ? BetterPlayerPanelColors.light(inherited.scaffoldBackgroundColor) : BetterPlayerPanelColors.dark;
  final base = ThemeData(
    useMaterial3: inherited.useMaterial3,
    brightness: light ? Brightness.light : Brightness.dark,
    fontFamily: inherited.textTheme.bodyMedium?.fontFamily,
  );
  final scheme = (light ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
    primary: accent,
    onPrimary: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black,
    surface: colors.panel,
    onSurface: colors.foreground,
    onSurfaceVariant: colors.muted,
    surfaceContainerLow: colors.panel,
    surfaceContainer: colors.panel,
    surfaceContainerHigh: colors.panel,
    surfaceContainerHighest: colors.raised,
    outline: colors.hairline,
    outlineVariant: colors.hairline,
    error: inherited.colorScheme.error,
  );
  final ink = colors.foreground;
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  const buttonText = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
  final radius = BorderRadius.circular(8);
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[colors],
    colorScheme: scheme,
    canvasColor: colors.panel,
    scaffoldBackgroundColor: colors.panel,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    iconTheme: IconThemeData(color: ink),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: colors.track,
      circularTrackColor: Colors.transparent,
    ),
    textSelectionTheme: inherited.textSelectionTheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.pill,
        foregroundColor: colors.onPill,
        disabledBackgroundColor: colors.hairline,
        disabledForegroundColor: colors.muted,
        minimumSize: const Size(0, 44),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.pill,
        foregroundColor: colors.onPill,
        minimumSize: const Size(0, 44),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: ink.withValues(alpha: .32)),
        minimumSize: const Size(0, 44),
        shape: pill,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink, textStyle: buttonText),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: ink)),
    sliderTheme: SliderThemeData(
      activeTrackColor: ink,
      inactiveTrackColor: colors.track,
      thumbColor: ink,
      overlayColor: ink.withValues(alpha: .12),
      activeTickMarkColor: Colors.transparent,
      inactiveTickMarkColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.onPill : colors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.pill : colors.track,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colors.pill : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(colors.onPill),
      side: BorderSide(color: colors.muted, width: 1.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.raised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: colors.muted),
      prefixIconColor: colors.muted,
      suffixIconColor: colors.muted,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: ink.withValues(alpha: .5)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: light ? const Color(0xFF2B2C2E) : const Color(0xFF2B2B2B),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      actionTextColor: Colors.white,
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(backgroundColor: colors.panel, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.panel,
      modalBackgroundColor: colors.panel,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: colors.hairline, space: 1),
    listTileTheme: ListTileThemeData(iconColor: colors.muted, textColor: ink),
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
    final colors = BetterPlayerPanelColors.of(context);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: height * .9),
          child: Material(
            color: colors.panel,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: colors.track, borderRadius: BorderRadius.circular(99)),
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
    final colors = BetterPlayerPanelColors.of(context);
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
                  style: TextStyle(color: colors.foreground, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                if (subtitle?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: closeLabel ?? MaterialLocalizations.of(context).closeButtonTooltip,
            color: colors.foreground,
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
    final colors = BetterPlayerPanelColors.of(context);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: colors.raised, shape: BoxShape.circle),
      child: Icon(icon, color: color ?? colors.secondary),
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
    final colors = BetterPlayerPanelColors.of(context);
    final titleColor = !widget.enabled
        ? colors.muted.withValues(alpha: .6)
        : widget.selected
        ? colors.foreground
        : colors.secondary;
    return Semantics(
      selected: widget.selected,
      button: true,
      child: Material(
        color: widget.selected ? colors.selectedFill : Colors.transparent,
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
                        ? Icon(PhosphorIcons.check(PhosphorIconsStyle.bold), size: 20, color: colors.foreground)
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
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_loading)
                    SizedBox.square(
                      key: const Key('better_player_selection_progress'),
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colors.foreground),
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
    final colors = BetterPlayerPanelColors.of(context);
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
                Icon(icon, size: 22, color: colors.muted),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.foreground, fontSize: 15, fontWeight: FontWeight.w500),
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
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(PhosphorIcons.caretRight(), size: 18, color: colors.muted),
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
        style: TextStyle(
          color: BetterPlayerPanelColors.of(context).foreground,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
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
    final colors = BetterPlayerPanelColors.of(context);
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
            style: TextStyle(color: colors.foreground, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}

/// Speeds as stops along a line, the chosen one a larger dot. Reads
/// left to right in every language, slowest first. Drag across the line to
/// move through the stops, or tap one.
class BetterPlayerSpeedSelector extends StatefulWidget {
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
  State<BetterPlayerSpeedSelector> createState() => _BetterPlayerSpeedSelectorState();
}

class _BetterPlayerSpeedSelectorState extends State<BetterPlayerSpeedSelector> {
  late double _selected = widget.selected;

  @override
  void didUpdateWidget(BetterPlayerSpeedSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _selected = widget.selected;
  }

  void _select(double speed) {
    if (speed == _selected) return;
    setState(() => _selected = speed);
    widget.onSelected(speed);
  }

  void _selectAt(double dx, double width) {
    if (width <= 0 || widget.speeds.isEmpty) return;
    final index = (dx / width * widget.speeds.length).floor().clamp(0, widget.speeds.length - 1);
    _select(widget.speeds[index]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BetterPlayerPanelColors.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inset = constraints.maxWidth / (widget.speeds.length * 2);
          return SizedBox(
            height: 76,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _selectAt(details.localPosition.dx, constraints.maxWidth),
              onHorizontalDragStart: (details) => _selectAt(details.localPosition.dx, constraints.maxWidth),
              onHorizontalDragUpdate: (details) => _selectAt(details.localPosition.dx, constraints.maxWidth),
              child: Stack(
                children: [
                  Positioned(
                    left: inset,
                    right: inset,
                    top: 21,
                    height: 2,
                    child: ColoredBox(color: colors.track),
                  ),
                  Row(
                    children: [
                      for (final speed in widget.speeds)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: speed == _selected,
                            label: speed == 1 ? '${BetterPlayerSpeedSelector.format(speed)} ${widget.normalLabel}' : BetterPlayerSpeedSelector.format(speed),
                            onTap: () => _select(speed),
                            excludeSemantics: true,
                            child: KeyedSubtree(
                              key: ValueKey('better_player_speed_${BetterPlayerSpeedSelector.format(speed)}'),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 44,
                                    child: Center(
                                      child: AnimatedContainer(
                                        duration: betterPlayerMotionDuration,
                                        width: speed == _selected ? 22 : 10,
                                        height: speed == _selected ? 22 : 10,
                                        decoration: BoxDecoration(
                                          color: speed == _selected ? colors.foreground : colors.muted,
                                          shape: BoxShape.circle,
                                          border: speed == _selected
                                              ? Border.all(color: colors.foreground.withValues(alpha: .35), width: 5)
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    speed == 1 ? '${BetterPlayerSpeedSelector.format(speed)} (${widget.normalLabel})' : BetterPlayerSpeedSelector.format(speed),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: speed == _selected ? colors.foreground : colors.muted,
                                      fontSize: 13,
                                      fontWeight: speed == _selected ? FontWeight.w700 : FontWeight.w500,
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
