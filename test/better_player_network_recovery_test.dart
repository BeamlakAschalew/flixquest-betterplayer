import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = _RecoveryChannel();

  setUp(() {
    native.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native.channel, native.handle);
  });

  Future<BetterPlayerController> createPlayer({bool live = false}) async {
    final controller = BetterPlayerController(
      const BetterPlayerConfiguration(autoPlay: true, handleLifecycle: false),
    );
    await controller.setupDataSource(
      BetterPlayerDataSource.network('https://example.test/movie.mp4', liveStream: live),
    );
    return controller;
  }

  testWidgets('live failures leave source refresh to the app without a competing retry loop', (tester) async {
    final controller = await createPlayer(live: true);
    await native.fail(recoverable: true);
    await tester.pump(const Duration(seconds: 30));
    expect(native.loads, 1);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('permanent native errors do not automatically reload the same URL', (tester) async {
    final controller = await createPlayer();
    await native.fail(recoverable: false);
    await tester.pump(const Duration(seconds: 30));
    expect(controller.videoPlayerController!.value.isErrorRecoverable, isFalse);
    expect(native.loads, 1);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('transient recovery retains position and a paused playback state', (tester) async {
    final controller = await createPlayer();
    await controller.seekTo(const Duration(seconds: 42));
    await controller.pause();
    final playCalls = native.playCalls;
    await native.fail(recoverable: true);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(native.loads, 2);
    expect(native.lastSeekMs, 42000);
    expect(controller.videoPlayerController!.value.isPlaying, isFalse);
    expect(native.playCalls, playCalls);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('failed reloads stop after three attempts rather than looping forever', (tester) async {
    final controller = await createPlayer();
    native.failReloads = true;
    await native.fail(recoverable: true);
    for (final seconds in [1, 3, 8, 30, 30]) {
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
    }
    expect(native.loads, 4);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('errors belonging to an old source are ignored', (tester) async {
    final controller = await createPlayer();
    final oldKey = native.sourceKey;
    await controller.setupDataSource(BetterPlayerDataSource.network('https://example.test/next.mp4'));
    await native.fail(recoverable: true, key: oldKey);
    await tester.pump(const Duration(seconds: 3));
    expect(controller.videoPlayerController!.value.hasError, isFalse);
    expect(native.loads, 2);
    controller.dispose();
    await tester.pump();
  });
}

class _RecoveryChannel extends MockMethodChannel {
  int loads = 0;
  int playCalls = 0;
  int? lastSeekMs;
  String? sourceKey;
  bool failReloads = false;

  void reset() {
    loads = 0;
    playCalls = 0;
    lastSeekMs = null;
    sourceKey = null;
    failReloads = false;
  }

  @override
  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'setDataSource') {
      loads++;
      sourceKey = ((call.arguments as Map)['dataSource'] as Map)['key'] as String?;
      if (failReloads && loads > 1) throw PlatformException(code: 'VideoError', message: 'Network unavailable');
      await _send(const StandardMethodCodec().encodeSuccessEnvelope({
        'event': 'initialized', 'key': sourceKey, 'duration': 600000,
        'width': 1280.0, 'height': 720.0,
      }));
      return null;
    }
    if (call.method == 'play') playCalls++;
    if (call.method == 'seekTo') lastSeekMs = (call.arguments as Map)['location'] as int?;
    if (call.method == 'position') return lastSeekMs ?? 0;
    if (call.method == 'absolutePosition') return 0;
    return super.handle(call);
  }

  Future<void> fail({required bool recoverable, String? key}) => _send(
    const StandardMethodCodec().encodeErrorEnvelope(
      code: 'VideoError', message: 'Synthetic playback failure',
      details: {'key': key ?? sourceKey, 'recoverable': recoverable},
    ),
  );

  Future<void> _send(ByteData data) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(eventsChannels.last.name, data, (_) {});
  }
}
