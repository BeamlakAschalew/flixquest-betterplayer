import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

const Duration betterPlayerMotionDuration = Duration(milliseconds: 220);

Color betterPlayerReadableAccent(Color configured, Color surface) {
  final contrast = configured.computeLuminance() > surface.computeLuminance()
      ? (configured.computeLuminance() + .05) / (surface.computeLuminance() + .05)
      : (surface.computeLuminance() + .05) / (configured.computeLuminance() + .05);
  return contrast >= 2 ? configured : Colors.white;
}

class BetterPlayerControlButton extends StatelessWidget {
  const BetterPlayerControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor = Colors.white,
    this.selected = false,
    this.backgroundColor,
    this.size = 48,
    this.iconSize = 24,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color iconColor;
  final bool selected;
  final Color? backgroundColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final background = selected ? iconColor.withValues(alpha: .14) : backgroundColor ?? Colors.transparent;
    final foreground = iconColor;
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      selected: selected,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkResponse(
              onTap: onPressed,
              radius: size * .56,
              containedInkWell: true,
              highlightShape: BoxShape.circle,
              child: Center(
                child: Icon(icon, size: iconSize, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BetterPlayerModalSheet extends StatelessWidget {
  const BetterPlayerModalSheet({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720, maxHeight: height * .88),
          child: Material(
            color: colors.surfaceContainerHigh,
            surfaceTintColor: colors.surfaceTint,
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
                  child: Row(
                    children: [
                      BetterPlayerIconSurface(icon: icon),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                        onPressed: () => Navigator.maybePop(context),
                        icon: Icon(PhosphorIcons.x()),
                      ),
                    ],
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BetterPlayerIconSurface extends StatelessWidget {
  const BetterPlayerIconSurface({required this.icon, this.selected = false, this.color, super.key});

  final IconData icon;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = color ?? colors.primary;
    return Container(
      width: 42,
      height: 42,
      decoration: selected ? BoxDecoration(color: accent.withValues(alpha: .14), shape: BoxShape.circle) : null,
      child: Icon(icon, color: selected ? accent : colors.onSurfaceVariant),
    );
  }
}

class BetterPlayerSelectionTile extends StatefulWidget {
  const BetterPlayerSelectionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.enabled = true,
    this.trailing,
    super.key,
  });

  final IconData icon;
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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: widget.selected ? colors.primary.withValues(alpha: .1) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.enabled && !_loading ? _handleTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                BetterPlayerIconSurface(icon: widget.icon, selected: widget.selected, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w600,
                          color: widget.enabled
                              ? widget.selected
                                    ? colors.primary
                                    : colors.onSurface
                              : colors.onSurface.withValues(alpha: .38),
                        ),
                      ),
                      if (widget.subtitle?.isNotEmpty == true) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_loading)
                  const SizedBox.square(
                    key: Key('better_player_selection_progress'),
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  widget.trailing ??
                      Icon(
                        widget.selected
                            ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                            : PhosphorIcons.caretRight(),
                        color: widget.selected ? colors.primary : colors.onSurfaceVariant,
                      ),
              ],
            ),
          ),
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
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BetterPlayerIconSurface(icon: icon),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

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
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 25),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: LinearProgressIndicator(
                    value: value!.clamp(0, 1),
                    minHeight: 5,
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
