import 'package:flutter/services.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';

/// Manager for handling screen brightness changes
class BetterPlayerBrightnessManager {
  static const MethodChannel _channel = MethodChannel('better_player_plus/brightness');

  static double? _originalBrightness;
  static double _currentBrightness = 0.5;

  /// Get current screen brightness (0.0 - 1.0)
  static Future<double> getBrightness() async {
    try {
      final double? brightness = await _channel.invokeMethod('getBrightness');
      if (brightness != null) {
        _currentBrightness = brightness;
        return brightness;
      }
    } catch (e) {
      BetterPlayerUtils.log('Failed to get brightness: $e');
    }
    return _currentBrightness;
  }

  /// Set screen brightness (0.0 - 1.0)
  static Future<void> setBrightness(double brightness) async {
    if (brightness < 0.0 || brightness > 1.0) {
      throw ArgumentError('Brightness must be between 0.0 and 1.0');
    }

    try {
      // Save original brightness on first change
      if (_originalBrightness == null) {
        _originalBrightness = await getBrightness();
      }

      await _channel.invokeMethod('setBrightness', {'brightness': brightness});
      _currentBrightness = brightness;
    } catch (e) {
      BetterPlayerUtils.log('Failed to set brightness: $e');
    }
  }

  /// Restore original brightness
  static Future<void> restoreOriginalBrightness() async {
    if (_originalBrightness != null) {
      try {
        await _channel.invokeMethod('setBrightness', {'brightness': _originalBrightness});
        _currentBrightness = _originalBrightness!;
        _originalBrightness = null;
      } catch (e) {
        BetterPlayerUtils.log('Failed to restore brightness: $e');
      }
    }
  }

  /// Reset the manager state
  static void reset() {
    _originalBrightness = null;
  }
}
