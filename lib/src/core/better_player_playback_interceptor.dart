import 'package:better_player_plus/src/core/better_player_controller.dart';

/// Takes over the playback requests that come from the player's own controls.
///
/// Set one on [BetterPlayerController.playbackInterceptor] when something
/// other than the viewer's tap decides what playback does, such as a
/// watch-together room where a pause has to reach every member. Each control
/// (play/pause buttons, the timelines, skip buttons, double-tap and swipe
/// seeks, hold-to-speed, the speed menus and the TV remote keys handled in
/// Dart) asks the interceptor first and acts on its own only when the
/// interceptor returns false.
///
/// The controller's plain [BetterPlayerController.play],
/// [BetterPlayerController.pause], [BetterPlayerController.seekTo] and
/// [BetterPlayerController.setSpeed] are never intercepted, so code that
/// steers playback deliberately keeps working and cannot be echoed back.
abstract class BetterPlayerPlaybackInterceptor {
  /// Return true if the request was handled (the control must not act itself).
  bool onPlayRequested(BetterPlayerController controller);

  /// Return true if the request was handled (the control must not act itself).
  bool onPauseRequested(BetterPlayerController controller);

  /// Return true if the request was handled (the control must not act itself).
  bool onSeekRequested(BetterPlayerController controller, Duration position);

  /// Return true if the request was handled (the control must not act itself).
  bool onSpeedRequested(BetterPlayerController controller, double speed);
}
