import 'package:better_player_plus/src/core/better_player_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

///Native Chromecast route button bound to one player instance.
class BetterPlayerCastButton extends StatelessWidget {
  const BetterPlayerCastButton({required this.controller, required this.color, required this.size, super.key});

  final BetterPlayerController controller;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final textureId = controller.videoPlayerController?.playerId;
    final configuration = controller.betterPlayerDataSource?.castConfiguration;
    if (textureId == null ||
        configuration?.enabled != true ||
        configuration?.enableChromecast != true ||
        defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    final creationParams = <String, Object>{'textureId': textureId, 'color': color.toARGB32()};
    return SizedBox.square(
      dimension: size,
      child: AndroidView(
        key: ValueKey<String>('better-player-chromecast-$textureId'),
        viewType: 'better_player_plus/chromecast_button',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
    );
  }
}
