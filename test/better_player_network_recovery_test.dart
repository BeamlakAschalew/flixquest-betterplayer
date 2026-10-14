import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'mock_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = _RecoveryChannel();

  setUp(() {
    native.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      native.channel,
      native.handle,
    );
  });

  Future<BetterPlayerController> createPlayer({
    bool live = false,
    Future<bool> Function(Duration? position)? sourceRecoveryHandler,
  }) async {
    final controller = BetterPlayerController(
      BetterPlayerConfiguration(autoPlay: true, handleLifecycle: false, sourceRecoveryHandler: sourceRecoveryHandler),
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

  testWidgets('failed reloads stop after two attempts and only then show the error', (tester) async {
    final controller = await createPlayer();
    native.failReloads = true;
    await native.fail(recoverable: true);
    await tester.pump();
    expect(controller.isRecoveringPlayback, isTrue);
    for (final seconds in [1, 4, 30, 30]) {
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
    }
    expect(native.loads, 3);
    expect(controller.isRecoveringPlayback, isFalse);
    expect(controller.videoPlayerController!.value.hasError, isTrue);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('offline failures wait for the network, however long, then reload at once', (tester) async {
    final controller = await createPlayer();
    await native.setOnline(false);
    await native.fail(recoverable: true);
    await tester.pump(const Duration(minutes: 10));
    expect(native.loads, 1);
    expect(controller.isRecoveringPlayback, isTrue);
    expect(controller.videoPlayerController!.value.isNetworkAvailable, isFalse);
    await native.setOnline(true);
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(native.loads, 2);
    expect(controller.videoPlayerController!.value.hasError, isFalse);
    await tester.pump();
    expect(controller.isRecoveringPlayback, isFalse);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('downloads opened through a network source never wait for the network', (tester) async {
    final controller = BetterPlayerController(const BetterPlayerConfiguration(autoPlay: true, handleLifecycle: false));
    await controller.setupDataSource(BetterPlayerDataSource.network('flixquest-offline://download-1'));
    expect(controller.streamsOverNetwork, isFalse);
    await native.setOnline(false);
    await native.fail(recoverable: true);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(native.loads, 2);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('coming back online retries an error that recovery had given up on', (tester) async {
    final controller = await createPlayer();
    native.failReloads = true;
    await native.fail(recoverable: true);
    for (final seconds in [1, 4, 30]) {
      await tester.pump(Duration(seconds: seconds));
      await tester.pump();
    }
    expect(native.loads, 3);
    await native.setOnline(false);
    native.failReloads = false;
    await native.setOnline(true);
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(native.loads, 4);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('a source the app can refresh is replaced before any error shows', (tester) async {
    Duration? refreshedAt;
    late BetterPlayerController controller;
    controller = await createPlayer(
      sourceRecoveryHandler: (position) async {
        refreshedAt = position;
        await controller.setupDataSource(
          BetterPlayerDataSource.network('https://example.test/fresh.mp4'),
          initialPosition: position,
        );
        return true;
      },
    );
    await controller.seekTo(const Duration(seconds: 42));
    // An expired link: reloading the same URL is pointless, so the app is
    // asked straight away.
    await native.fail(recoverable: false);
    await tester.pump();
    await tester.pump();
    expect(refreshedAt, const Duration(seconds: 42));
    expect(native.loads, 2);
    expect(native.lastSeekMs, 42000);
    expect(controller.videoPlayerController!.value.hasError, isFalse);
    await tester.pump();
    expect(controller.isRecoveringPlayback, isFalse);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('the app refresh is tried once per failure', (tester) async {
    var refreshes = 0;
    final controller = await createPlayer(
      sourceRecoveryHandler: (_) async {
        refreshes++;
        return false;
      },
    );
    await native.fail(recoverable: false);
    await tester.pump(const Duration(seconds: 30));
    expect(refreshes, 1);
    expect(controller.isRecoveringPlayback, isFalse);
    expect(controller.videoPlayerController!.value.hasError, isTrue);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('retry from the error starts recovery again', (tester) async {
    final controller = await createPlayer();
    await native.fail(recoverable: false);
    await tester.pump(const Duration(seconds: 30));
    expect(native.loads, 1);
    expect(controller.isRecoveringPlayback, isFalse);
    // A viewer asking again reloads even an error recovery would not retry.
    await controller.retryDataSource();
    expect(controller.isRecoveringPlayback, isTrue);
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(native.loads, 2);
    expect(controller.videoPlayerController!.value.hasError, isFalse);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('a resume point survives a source that failed before it started', (tester) async {
    final controller = await createPlayer();
    native.holdInitialization = true;
    unawaited(
      controller
          .setupDataSource(
            BetterPlayerDataSource.network('https://example.test/next.mp4'),
            initialPosition: const Duration(minutes: 5),
          )
          .catchError((Object _) {}),
    );
    await tester.pump();
    await native.fail(recoverable: true);
    native.holdInitialization = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(native.loads, 3);
    expect(native.lastSeekMs, const Duration(minutes: 5).inMilliseconds);
    controller.dispose();
    await tester.pump();
  });

  testWidgets('the controls show loading, not the error, until recovery gives up', (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    final controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        handleLifecycle: false,
        errorBuilder: (_, _) => const Text('playback error'),
      ),
    );
    await controller.setupDataSource(BetterPlayerDataSource.network('https://example.test/movie.mp4'));
    await tester.pumpWidget(MaterialApp(home: BetterPlayer(controller: controller)));
    await tester.pump(const Duration(milliseconds: 500));

    await native.setOnline(false);
    await native.fail(recoverable: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('playback error'), findsNothing);
    expect(find.byKey(const Key('better_player_network_wait')), findsOneWidget);

    native.failReloads = true;
    await native.setOnline(true);
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(find.text('playback error'), findsNothing);
    expect(find.byKey(const Key('better_player_network_wait')), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.pump();
    expect(native.loads, 3);
    expect(find.text('playback error'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

class _RecoveryChannel extends MockMethodChannel {
  int loads = 0;
  int playCalls = 0;
  int? lastSeekMs;
  String? sourceKey;
  bool failReloads = false;
  bool holdInitialization = false;

  void reset() {
    loads = 0;
    playCalls = 0;
    lastSeekMs = null;
    sourceKey = null;
    failReloads = false;
    holdInitialization = false;
  }

  @override
  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'setDataSource') {
      loads++;
      sourceKey = ((call.arguments as Map)['dataSource'] as Map)['key'] as String?;
      if (failReloads && loads > 1) throw PlatformException(code: 'VideoError', message: 'Network unavailable');
      if (holdInitialization) return null;
      await _send(
        const StandardMethodCodec().encodeSuccessEnvelope({
          'event': 'initialized',
          'key': sourceKey,
          'duration': 600000,
          'width': 1280.0,
          'height': 720.0,
        }),
      );
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
      code: 'VideoError',
      message: 'Synthetic playback failure',
      details: {'key': key ?? sourceKey, 'recoverable': recoverable},
    ),
  );

  Future<void> setOnline(bool online) =>
      _send(const StandardMethodCodec().encodeSuccessEnvelope({'event': 'connectivityChanged', 'online': online}));

  Future<void> _send(ByteData data) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      eventsChannels.last.name,
      data,
      (_) {},
    );
  }
}
