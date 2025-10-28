import 'package:better_player_example/constants.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

class PictureInPicturePage extends StatefulWidget {
  const PictureInPicturePage({super.key});

  @override
  State<PictureInPicturePage> createState() => _PictureInPicturePageState();
}

class _PictureInPicturePageState extends State<PictureInPicturePage> {
  late BetterPlayerController _betterPlayerController;
  final GlobalKey _betterPlayerKey = GlobalKey();

  @override
  void initState() {
    const BetterPlayerConfiguration betterPlayerConfiguration = BetterPlayerConfiguration(
      aspectRatio: 16 / 9,
      fit: BoxFit.contain,
    );
    final BetterPlayerDataSource dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      Constants.elephantDreamVideoUrl,
    );
    _betterPlayerController = BetterPlayerController(betterPlayerConfiguration);
    _betterPlayerController.setupDataSource(dataSource);
    _betterPlayerController.setBetterPlayerGlobalKey(_betterPlayerKey);
    super.initState();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Picture in Picture player')),
    body: Column(
      children: [
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Example which shows how to use PiP.', style: TextStyle(fontSize: 16)),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: BetterPlayer(controller: _betterPlayerController, key: _betterPlayerKey),
        ),
        ElevatedButton(
          child: const Text('Show PiP'),
          onPressed: () {
            _betterPlayerController.enablePictureInPicture(_betterPlayerKey);
          },
        ),
        ElevatedButton(
          child: const Text('Disable PiP'),
          onPressed: () async {
            _betterPlayerController.disablePictureInPicture();
          },
        ),
      ],
    ),
  );
}
