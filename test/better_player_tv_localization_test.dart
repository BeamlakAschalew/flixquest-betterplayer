import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

const _strings = BetterPlayerControlsStrings(
  play: 'Reproducir',
  pause: 'Pausar',
  seekBack: 'Retroceder {seconds} segundos',
  seekForward: 'Avanzar {seconds} segundos',
  settings: 'Ajustes',
  playerSettings: 'Ajustes del reproductor',
  playbackSpeed: 'Velocidad de reproducción',
  subtitles: 'Subtítulos',
  subtitleNumber: 'Subtítulo {number}',
  audio: 'Audio',
  audioTrack: 'Pista de audio',
  defaultAudio: 'Audio predeterminado',
  off: 'Desactivados',
  quality: 'Calidad',
  videoQuality: 'Calidad de vídeo',
  automatic: 'Automática',
  cropAndFit: 'Recortar y ajustar',
  fit: 'Ajustar',
  fitDescription: 'Mostrar toda la imagen',
  cropToFill: 'Recortar para llenar',
  stretch: 'Estirar',
  live: 'EN DIRECTO',
  playbackPosition: 'Posición de reproducción',
  positionOf: '{position} de {duration}',
);

Finder _control(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

Future<void> _back(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('TV menu names its close control and loading status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BetterPlayerTvMenu(
            title: 'Subtítulos',
            strings: const BetterPlayerControlsStrings(close: 'Cerrar', loadingSubtitles: 'Cargando subtítulos'),
            loadingIndex: 0,
            onClose: () {},
            items: [BetterPlayerTvMenuItem(label: 'Español', icon: Icons.subtitles, onSelected: () {})],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_control('Cerrar'), findsOneWidget);
    expect(_control('Cargando subtítulos'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final live in [false, true]) {
    testWidgets('TV ${live ? 'live' : 'video'} controls use the supplied translations', (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = BetterPlayerMockController(
        const BetterPlayerConfiguration(
          controlsConfiguration: BetterPlayerControlsConfiguration(
            showControlsOnInitialize: true,
            controlsHideTime: Duration(minutes: 1),
            strings: _strings,
            enableAudioTracks: true,
            enableQualities: true,
            enableCrop: true,
          ),
        ),
      );
      final video = MockVideoPlayerController();
      controller.videoPlayerController = video;
      await controller.setupDataSource(
        BetterPlayerDataSource.network('https://example.com/video.mp4', liveStream: live),
      );
      video.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);
      controller.betterPlayerSubtitlesSourceList.add(
        BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.network, urls: ['https://example.com/a.srt']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BetterPlayerTvControls(controller: controller, onControlsVisibilityChanged: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(_control('Pausar'), findsOneWidget);
      expect(_control('Ajustes'), findsOneWidget);
      if (live) {
        expect(find.text('EN DIRECTO'), findsOneWidget);
        expect(find.byType(BetterPlayerTvProgressBar), findsNothing);
      } else {
        expect(_control('Retroceder 10 segundos'), findsOneWidget);
        expect(_control('Avanzar 10 segundos'), findsOneWidget);
        final position = tester.widget<Semantics>(_control('Posición de reproducción'));
        expect(position.properties.value, '00:00 de 02:00');
      }
      await tester.tap(_control('Ajustes'));
      await tester.pumpAndSettle();
      expect(find.text('Ajustes del reproductor'), findsOneWidget);
      expect(find.text('Velocidad de reproducción'), findsOneWidget);
      await _back(tester);

      await tester.tap(_control('Subtítulos'));
      await tester.pumpAndSettle();
      expect(find.text('Desactivados'), findsOneWidget);
      expect(find.text('Subtítulo 1'), findsOneWidget);
      await _back(tester);

      await tester.tap(_control('Audio'));
      await tester.pumpAndSettle();
      expect(find.text('Pista de audio'), findsOneWidget);
      expect(find.text('Audio predeterminado'), findsOneWidget);
      await _back(tester);

      await tester.tap(_control('Calidad'));
      await tester.pumpAndSettle();
      expect(find.text('Calidad de vídeo'), findsOneWidget);
      expect(find.text('Automática'), findsOneWidget);
      await _back(tester);

      await tester.tap(_control('Recortar y ajustar'));
      await tester.pumpAndSettle();
      expect(find.text('Mostrar toda la imagen'), findsOneWidget);
      expect(find.text('Recortar para llenar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
