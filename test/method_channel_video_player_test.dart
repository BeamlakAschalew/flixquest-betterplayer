import 'package:better_player_plus/src/video_player/method_channel_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('better_player_channel');
  final player = MethodChannelVideoPlayer();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> returnAbsolutePosition(int milliseconds) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'absolutePosition');
      return milliseconds;
    });
  }

  test('returns a valid absolute playback position', () async {
    const milliseconds = 1700000000000;
    await returnAbsolutePosition(milliseconds);

    expect(await player.getAbsolutePosition(1), DateTime.fromMillisecondsSinceEpoch(milliseconds));
  });

  test('ignores an absolute playback position outside DateTime range', () async {
    await returnAbsolutePosition(9223372036854775006);

    expect(await player.getAbsolutePosition(1), isNull);
  });
}
