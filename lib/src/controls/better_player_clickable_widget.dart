// Flutter imports:
import 'package:flutter/material.dart';

class BetterPlayerMaterialClickableWidget extends StatelessWidget {
  final Widget child;
  final void Function() onTap;

  const BetterPlayerMaterialClickableWidget({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.hardEdge,
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: child),
    );
  }
}
