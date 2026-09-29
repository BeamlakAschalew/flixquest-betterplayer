import 'package:better_player_plus/src/video_player/method_channel_video_player.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
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

  test('flushes the network bytes waiting for the next batch', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'flushNetworkUsage');
      expect(call.arguments, <String, dynamic>{'textureId': 1});
      return 5000000000;
    });

    expect(await player.flushNetworkUsage(1), 5000000000);
  });

  test('reports network usage as unmeasured where the platform lacks it', () async {
    expect(await player.flushNetworkUsage(1), isNull);
  });

  test('parses batched network usage events', () async {
    const eventChannel = EventChannel('better_player_channel/videoEvents1');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (_, sink) => sink.success(<String, dynamic>{'event': 'networkUsage', 'bytes': 16777216}),
      ),
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(eventChannel, null),
    );

    final event = await player.videoEventsFor(1).first;

    expect(event.eventType, VideoEventType.networkUsage);
    expect(event.bytesTransferred, 16777216);
  });
}
