import 'package:flutter/services.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';

/// Manager for handling device system volume changes
class BetterPlayerVolumeManager {
  static const MethodChannel _channel = MethodChannel('better_player_plus/volume');

  static double? _originalVolume;
  static double _currentVolume = 0.5;

  /// Get current device volume (0.0 - 1.0)
  static Future<double> getVolume() async {
    try {
      final result = await _channel.invokeMethod('getVolume');
      BetterPlayerUtils.log('BetterPlayerVolumeManager.getVolume: raw result=$result, type=${result.runtimeType}');
      final double? volume = result is num ? result.toDouble() : null;
      if (volume != null) {
        _currentVolume = volume;
        BetterPlayerUtils.log('BetterPlayerVolumeManager.getVolume: returning $volume');
        return volume;
      }
    } catch (e) {
      BetterPlayerUtils.log('Failed to get volume: $e');
    }
    return _currentVolume;
  }

  /// Set device volume (0.0 - 1.0)
  static Future<void> setVolume(double volume) async {
    if (volume < 0.0 || volume > 1.0) {
      throw ArgumentError('Volume must be between 0.0 and 1.0');
    }

    try {
      // Save original volume on first change
      if (_originalVolume == null) {
        _originalVolume = await getVolume();
        BetterPlayerUtils.log('BetterPlayerVolumeManager: saved original volume=$_originalVolume');
      }

      BetterPlayerUtils.log('BetterPlayerVolumeManager.setVolume: setting to $volume');
      await _channel.invokeMethod('setVolume', {'volume': volume});
      _currentVolume = volume;
    } catch (e) {
      BetterPlayerUtils.log('Failed to set volume: $e');
    }
  }

  /// Restore original volume
  static Future<void> restoreOriginalVolume() async {
    if (_originalVolume != null) {
      try {
        await _channel.invokeMethod('setVolume', {'volume': _originalVolume});
        _originalVolume = null;
      } catch (e) {
        BetterPlayerUtils.log('Failed to restore volume: $e');
      }
    }
  }

  /// Reset the manager state
  static void reset() {
    _originalVolume = null;
  }
}
