import 'package:better_player_example/constants.dart';
import 'package:better_player_example/utils.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

class BasicPlayerPage extends StatefulWidget {
  const BasicPlayerPage({super.key});

  @override
  State<BasicPlayerPage> createState() => _BasicPlayerPageState();
}

class _BasicPlayerPageState extends State<BasicPlayerPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Basic player')),
    body: Column(
      children: [
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Basic player created with the simplest factory method. Shows video from URL.',
            style: TextStyle(fontSize: 16),
          ),
        ),
        AspectRatio(aspectRatio: 16 / 9, child: BetterPlayer.network(Constants.forBiggerBlazesUrl)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Next player shows video from file.', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        FutureBuilder<String>(
          future: Utils.getFileUrl(Constants.fileTestVideoUrl),
          builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
            if (snapshot.data != null) {
              return BetterPlayer.file(snapshot.data!);
            } else {
              return const SizedBox();
            }
          },
        ),
      ],
    ),
  );
}
