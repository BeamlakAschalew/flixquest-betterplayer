import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ambient glow is opt-in and copyable', () {
    const configuration = BetterPlayerConfiguration();

    expect(configuration.enableAmbientGlow, isFalse);
    expect(configuration.copyWith(enableAmbientGlow: true).enableAmbientGlow, isTrue);
  });

  test('ambient glow can be toggled without rebuilding the controller', () {
    final controller = BetterPlayerController(const BetterPlayerConfiguration(enableAmbientGlow: true));
    addTearDown(controller.dispose);

    expect(controller.ambientGlowEnabled, isTrue);
    controller.setAmbientGlowEnabled(false);
    expect(controller.ambientGlowEnabled, isFalse);
  });
}
