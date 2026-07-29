import 'package:better_player_plus/src/configuration/better_player_controls_configuration.dart';
import 'package:better_player_plus/src/controls/better_player_material_controls.dart';
import 'package:flutter/widgets.dart';

/// iOS entry point retained for API compatibility.
///
/// Both platform themes intentionally share the modern package-owned controls
/// so player actions, sheets, accessibility, and iconography stay consistent.
class BetterPlayerCupertinoControls extends StatelessWidget {
  const BetterPlayerCupertinoControls({
    required this.onControlsVisibilityChanged,
    required this.controlsConfiguration,
    super.key,
  });

  final Function(bool visibility) onControlsVisibilityChanged;
  final BetterPlayerControlsConfiguration controlsConfiguration;

  @override
  Widget build(BuildContext context) => BetterPlayerMaterialControls(
    onControlsVisibilityChanged: onControlsVisibilityChanged,
    onFullScreenChanged: (_) {},
    controlsConfiguration: controlsConfiguration,
  );
}
