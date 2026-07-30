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
    this.accentColor = Colors.deepOrange,
    super.key,
  });

  final String title;
  final List<BetterPlayerTvMenuItem> items;
  final VoidCallback onClose;
  final VoidCallback? onBack;
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
    return FocusScope(
      node: _focusScopeNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: ColoredBox(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 460,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xf5161716),
              border: Border(left: BorderSide(color: Colors.white12)),
            ),
            padding: const EdgeInsets.fromLTRB(30, 30, 30, 24),
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
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
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
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return _TvMenuTile(
                        item: item,
                        accentColor: widget.accentColor,
                        focusNode: _itemFocusNodes[index],
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
  const _TvMenuTile({required this.item, required this.accentColor, required this.focusNode});

  final BetterPlayerTvMenuItem item;
  final Color accentColor;
  final FocusNode focusNode;

  @override
  State<_TvMenuTile> createState() => _TvMenuTileState();
}

class _TvMenuTileState extends State<_TvMenuTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.item.enabled ? Colors.white : Colors.white38;
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
              widget.item.onSelected();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.item.enabled ? widget.item.onSelected : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: widget.item.selected ? widget.accentColor.withValues(alpha: 0.22) : const Color(0xff262725),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _focused ? widget.accentColor : Colors.transparent, width: 3),
            ),
            child: Row(
              children: <Widget>[
                Icon(widget.item.icon, color: widget.item.selected ? widget.accentColor : foreground, size: 26),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: foreground, fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                      if (widget.item.subtitle != null) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          widget.item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 15),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.item.selected)
                  Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: widget.accentColor, size: 24)
                else if (widget.item.showsNext)
                  const Icon(PhosphorIconsRegular.caretRight, color: Colors.white54, size: 20),
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
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xff292a28),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 3),
        ),
        child: const Icon(PhosphorIconsRegular.x, color: Colors.white),
      ),
    );
  }
}
