// Flutter imports:
import 'package:flutter/material.dart';

class BetterPlayerMaterialClickableWidget extends StatelessWidget {
  const BetterPlayerMaterialClickableWidget({super.key, required this.onTap, required this.child});
  final Widget child;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) => Material(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(200)),
    clipBehavior: Clip.hardEdge,
    color: Colors.transparent,
    child: InkWell(borderRadius: BorderRadius.circular(90), onTap: onTap, child: child),
  );
}
