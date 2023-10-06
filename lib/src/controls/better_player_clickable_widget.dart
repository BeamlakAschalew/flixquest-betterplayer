// Flutter imports:
import 'package:flutter/material.dart';

class BetterPlayerMaterialClickableWidget extends StatelessWidget {
  final Widget child;
  final void Function() onTap;

  const BetterPlayerMaterialClickableWidget({
    Key? key,
    required this.onTap,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(200),
      ),
      clipBehavior: Clip.hardEdge,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(90),
        onTap: onTap,
        child: child,
      ),
    );
  }
}
