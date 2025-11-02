import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

import '../constants.dart';

class GestureControlsPage extends StatefulWidget {
  @override
  _GestureControlsPageState createState() => _GestureControlsPageState();
}

class _GestureControlsPageState extends State<GestureControlsPage> {
  late BetterPlayerController _betterPlayerController;

  @override
  void initState() {
    super.initState();

    // Configure gesture controls
    final gestureConfiguration = BetterPlayerGestureConfiguration(
      enableVolumeSwipe: true,
      enableBrightnessSwipe: true,
      enableSeekSwipe: true,
      volumeSwipeSensitivity: 0.5,
      brightnessSwipeSensitivity: 0.5,
      seekSwipeSensitivity: 1.0,
      swipeAreaWidthPercentage: 0.35,
    );

    BetterPlayerConfiguration betterPlayerConfiguration = BetterPlayerConfiguration(
      aspectRatio: 16 / 9,
      fit: BoxFit.contain,
      autoPlay: true,
      controlsConfiguration: BetterPlayerControlsConfiguration(
        gestureConfiguration: gestureConfiguration,
        enableSkips: true,
        enableFullscreen: true,
      ),
    );

    BetterPlayerDataSource dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      Constants.forBiggerBlazesUrl,
      liveStream: false,
    );

    _betterPlayerController = BetterPlayerController(betterPlayerConfiguration, betterPlayerDataSource: dataSource);
  }

  @override
  void dispose() {
    _betterPlayerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Gesture Controls Demo")),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: BetterPlayer(controller: _betterPlayerController),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gesture Controls Guide', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 16),
                        _buildGestureInstruction(
                          Icons.brightness_6,
                          'Brightness Control',
                          'Swipe up/down on the LEFT side of the screen to adjust brightness',
                        ),
                        SizedBox(height: 12),
                        _buildGestureInstruction(
                          Icons.volume_up,
                          'Volume Control',
                          'Swipe up/down on the RIGHT side of the screen to adjust volume',
                        ),
                        SizedBox(height: 12),
                        _buildGestureInstruction(
                          Icons.fast_forward,
                          'Seek Forward/Backward',
                          'Swipe left/right in the CENTER of the screen to seek through the video',
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Features', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('• Visual feedback overlay shows your adjustments'),
                        Text('• Smooth and responsive gesture detection'),
                        Text('• Configurable sensitivity and swipe areas'),
                        Text('• Works in both portrait and landscape modes'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGestureInstruction(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: Colors.blue),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 4),
              Text(description, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
        ),
      ],
    );
  }
}
