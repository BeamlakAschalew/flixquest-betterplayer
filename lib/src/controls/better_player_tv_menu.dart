import 'package:better_player_plus/src/controls/better_player_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BetterPlayerTvMenuItem {
  const BetterPlayerTvMenuItem({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.subtitle,
    this.selected = false,
    this.enabled = true,
    this.showsNext = false,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onSelected;
  final bool selected;
  final bool enabled;
  final bool showsNext;
}

class BetterPlayerTvMenu extends StatefulWidget {
  const BetterPlayerTvMenu({
    required this.title,
    required this.items,
    required this.onClose,
    this.onBack,
    this.loadingIndex,
    this.accentColor = Colors.deepOrange,
    super.key,
  });

  final String title;
  final List<BetterPlayerTvMenuItem> items;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  /// The row currently being applied. Other selections wait until it finishes.
  final int? loadingIndex;
  final Color accentColor;

  @override
  State<BetterPlayerTvMenu> createState() => _BetterPlayerTvMenuState();
}

class _BetterPlayerTvMenuState extends State<BetterPlayerTvMenu> {
  late final FocusScopeNode _focusScopeNode;
  late final FocusNode _closeFocusNode;
  final List<FocusNode> _itemFocusNodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _focusScopeNode = FocusScopeNode(debugLabel: 'Better Player TV menu');
    _closeFocusNode = FocusNode(debugLabel: 'Better Player TV menu close');
    _syncItemFocusNodes();
    _scheduleInitialFocus();
  }

  @override
  void didUpdateWidget(BetterPlayerTvMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncItemFocusNodes();
    if (oldWidget.title != widget.title || !identical(oldWidget.items, widget.items)) {
      _scheduleInitialFocus();
    }
  }

  void _syncItemFocusNodes() {
    while (_itemFocusNodes.length < widget.items.length) {
      _itemFocusNodes.add(FocusNode(debugLabel: 'Better Player TV menu item ${_itemFocusNodes.length + 1}'));
    }
    while (_itemFocusNodes.length > widget.items.length) {
      _itemFocusNodes.removeLast().dispose();
    }
    for (var index = 0; index < _itemFocusNodes.length; index++) {
      _itemFocusNodes[index].canRequestFocus = widget.items[index].enabled;
    }
  }

  void _scheduleInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedIndex = widget.items.indexWhere((item) => item.enabled && item.selected);
      final firstEnabledIndex = widget.items.indexWhere((item) => item.enabled);
      final targetIndex = selectedIndex >= 0 ? selectedIndex : firstEnabledIndex;
      if (targetIndex >= 0) {
        _itemFocusNodes[targetIndex].requestFocus();
      } else {
        _closeFocusNode.requestFocus();
      }
    });
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.browserBack) {
      (widget.onBack ?? widget.onClose)();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      // The menu is modal on TV. Keep horizontal navigation from escaping to
      // the controls that remain mounted behind it.
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveFocus(int direction) {
    var currentIndex = -1;
    for (var index = 0; index < _itemFocusNodes.length; index++) {
      if (_itemFocusNodes[index].hasFocus) {
        currentIndex = index;
        break;
      }
    }

    if (direction < 0 && currentIndex <= 0) {
      _closeFocusNode.requestFocus();
      return;
    }
    if (direction > 0 && currentIndex < 0) {
      _requestFirstEnabledFocus();
      return;
    }

    for (var index = currentIndex + direction; index >= 0 && index < _itemFocusNodes.length; index += direction) {
      if (widget.items[index].enabled) {
        _itemFocusNodes[index].requestFocus();
        return;
      }
    }
  }

  void _requestFirstEnabledFocus() {
    final index = widget.items.indexWhere((item) => item.enabled);
    if (index >= 0) _itemFocusNodes[index].requestFocus();
  }

  @override
  void dispose() {
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    _closeFocusNode.dispose();
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BetterPlayerTvPanelColors.of(context);
    return FocusScope(
      node: _focusScopeNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: ColoredBox(
        color: const Color(0x66000000),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 420,
            height: double.infinity,
            color: colors.panel,
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.foreground, fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TvMenuCloseButton(focusNode: _closeFocusNode, onPressed: widget.onClose),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return _TvMenuTile(
                        item: item,
                        accentColor: widget.accentColor,
                        focusNode: _itemFocusNodes[index],
                        isLoading: widget.loadingIndex == index,
                        onSelected: () {
                          if (widget.loadingIndex == null) item.onSelected();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvMenuTile extends StatefulWidget {
  const _TvMenuTile({
    required this.item,
    required this.accentColor,
    required this.focusNode,
    required this.isLoading,
    required this.onSelected,
  });

  final BetterPlayerTvMenuItem item;
  final Color accentColor;
  final FocusNode focusNode;
  final bool isLoading;
  final VoidCallback onSelected;

  @override
  State<_TvMenuTile> createState() => _TvMenuTileState();
}

class _TvMenuTileState extends State<_TvMenuTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Focus fills the row with the page's ink (white on a dark page), as
    // everywhere else on the TV; the chosen option carries a check rather
    // than a colour.
    final colors = BetterPlayerTvPanelColors.of(context);
    final foreground = !widget.item.enabled
        ? colors.disabled
        : _focused
        ? colors.onFocus
        : colors.foreground;
    final secondary = _focused ? colors.onFocusMuted : colors.muted;
    return Semantics(
      button: true,
      selected: widget.item.selected,
      label: widget.item.label,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: widget.item.enabled,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onSelected();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.item.enabled ? widget.onSelected : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _focused ? colors.focusFill : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: <Widget>[
                Icon(widget.item.icon, color: foreground, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 17,
                          fontWeight: widget.item.selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (widget.item.subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          widget.item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: secondary, fontSize: 14),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.isLoading)
                  Semantics(
                    liveRegion: true,
                    label: 'Loading subtitles',
                    child: SizedBox.square(
                      key: const Key('tv_subtitle_selection_progress'),
                      dimension: 20,
                      child: CircularProgressIndicator(color: foreground, strokeWidth: 2),
                    ),
                  )
                else if (widget.item.selected)
                  Icon(PhosphorIcons.check(PhosphorIconsStyle.bold), color: foreground, size: 20)
                else if (widget.item.showsNext)
                  Icon(PhosphorIconsRegular.caretRight, color: secondary, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvMenuCloseButton extends StatefulWidget {
  const _TvMenuCloseButton({required this.focusNode, required this.onPressed});

  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  State<_TvMenuCloseButton> createState() => _TvMenuCloseButtonState();
}

class _TvMenuCloseButtonState extends State<_TvMenuCloseButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = BetterPlayerTvPanelColors.of(context);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _focused = focused),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _focused ? colors.focusFill : colors.idleFill,
          shape: BoxShape.circle,
        ),
        child: Icon(PhosphorIconsRegular.x, color: _focused ? colors.onFocus : colors.foreground),
      ),
    );
  }
}
