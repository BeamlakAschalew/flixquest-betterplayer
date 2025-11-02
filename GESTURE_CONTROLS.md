# Gesture-Based Controls Feature

This document explains the gesture-based controls feature added to Better Player Plus, which allows users to control volume, brightness, and seeking through intuitive swipe gestures.

## Features

### 1. Volume Control (Right Side Swipe)

- **Gesture**: Vertical swipe on the right side of the video player
- **Action**: Adjusts video volume from 0% to 100%
- **Visual Feedback**: Shows volume icon and progress bar with percentage

### 2. Brightness Control (Left Side Swipe)

- **Gesture**: Vertical swipe on the left side of the video player
- **Action**: Adjusts screen brightness from 0% to 100%
- **Visual Feedback**: Shows brightness icon and progress bar with percentage

### 3. Seek Control (Center Horizontal Swipe)

- **Gesture**: Horizontal swipe in the center area of the video player
- **Action**: Seeks forward or backward in the video
- **Visual Feedback**: Shows fast-forward/rewind icon with seconds

## Configuration

### Basic Usage

```dart
import 'package:better_player_plus/better_player_plus.dart';

// Configure gesture controls
final gestureConfiguration = BetterPlayerGestureConfiguration(
  enableVolumeSwipe: true,
  enableBrightnessSwipe: true,
  enableSeekSwipe: true,
);

// Add to controls configuration
final controlsConfiguration = BetterPlayerControlsConfiguration(
  gestureConfiguration: gestureConfiguration,
);

// Create player configuration
final betterPlayerConfiguration = BetterPlayerConfiguration(
  controlsConfiguration: controlsConfiguration,
);

// Create player
final controller = BetterPlayerController(
  betterPlayerConfiguration,
  betterPlayerDataSource: dataSource,
);
```

### Advanced Configuration

```dart
final gestureConfiguration = BetterPlayerGestureConfiguration(
  // Enable/disable individual gestures
  enableVolumeSwipe: true,
  enableBrightnessSwipe: true,
  enableSeekSwipe: true,

  // Adjust sensitivity (0.1 - 2.0)
  volumeSwipeSensitivity: 0.5,        // Default: 0.5
  brightnessSwipeSensitivity: 0.5,    // Default: 0.5
  seekSwipeSensitivity: 1.0,          // Default: 1.0

  // Minimum swipe distance to trigger gesture (in pixels)
  minimumSwipeDistance: 10.0,         // Default: 10.0

  // Duration to show feedback overlay
  feedbackDuration: Duration(milliseconds: 500),  // Default: 500ms

  // Width percentage for left/right swipe areas (0.2 - 0.5)
  swipeAreaWidthPercentage: 0.35,     // Default: 0.35 (35%)
);
```

## Configuration Options

### BetterPlayerGestureConfiguration Properties

| Property                     | Type       | Default | Description                                            |
| ---------------------------- | ---------- | ------- | ------------------------------------------------------ |
| `enableVolumeSwipe`          | `bool`     | `true`  | Enable volume control via right-side vertical swipe    |
| `enableBrightnessSwipe`      | `bool`     | `true`  | Enable brightness control via left-side vertical swipe |
| `enableSeekSwipe`            | `bool`     | `true`  | Enable seek control via horizontal swipe               |
| `volumeSwipeSensitivity`     | `double`   | `0.5`   | Volume adjustment sensitivity (0.1 - 2.0)              |
| `brightnessSwipeSensitivity` | `double`   | `0.5`   | Brightness adjustment sensitivity (0.1 - 2.0)          |
| `seekSwipeSensitivity`       | `double`   | `1.0`   | Seek adjustment sensitivity (0.1 - 2.0)                |
| `minimumSwipeDistance`       | `double`   | `10.0`  | Minimum distance in pixels to trigger gesture          |
| `feedbackDuration`           | `Duration` | `500ms` | Duration to display feedback overlay                   |
| `swipeAreaWidthPercentage`   | `double`   | `0.35`  | Width percentage of left/right swipe areas (0.2 - 0.5) |

## Platform Support

- ✅ **Android**: Fully supported
- ✅ **iOS**: Fully supported
- ❌ **Web**: Not supported (brightness control requires native APIs)

## How It Works

### Screen Layout

```
┌─────────────────────────────────────┐
│ ◄── Brightness   |   Seek  | Volume ──►│
│     Area (35%)   | Area  | Area (35%) │
│                  |        |            │
│                  |        |            │
│       LEFT       | CENTER |   RIGHT    │
│                  |        |            │
│                  |        |            │
└─────────────────────────────────────┘
```

### Gesture Detection Zones

1. **Left Zone** (35% width): Brightness control

   - Swipe up: Increase brightness
   - Swipe down: Decrease brightness

2. **Center Zone** (30% width): Seek control

   - Swipe right: Seek forward
   - Swipe left: Seek backward

3. **Right Zone** (35% width): Volume control
   - Swipe up: Increase volume
   - Swipe down: Decrease volume

## Visual Feedback

The gesture controls provide real-time visual feedback:

### Volume Feedback

- Icon: Volume mute/up icon
- Progress bar showing current volume level
- Percentage text (0-100%)

### Brightness Feedback

- Icon: Brightness low/high icon
- Progress bar showing current brightness level
- Percentage text (0-100%)

### Seek Feedback

- Icon: Fast-forward/rewind icon
- Text showing seek amount in seconds (e.g., "+10s" or "-5s")

## Implementation Details

### Brightness Management

The brightness control is implemented using platform-specific APIs:

- **Android**: `WindowManager.LayoutParams.screenBrightness`
- **iOS**: `UIScreen.main.brightness`

The original brightness is automatically saved when first changed and restored when the player is disposed.

### Volume Management

Volume is controlled through the existing Better Player volume API, which uses:

- **Android**: ExoPlayer's volume control
- **iOS**: AVPlayer's volume control

### Seek Management

Seeking uses the Better Player's `seekTo` method with calculated durations based on swipe distance and sensitivity.

## Best Practices

1. **Sensitivity Tuning**: Adjust sensitivity based on your app's UX requirements

   - Lower sensitivity (0.3-0.5): More precise control, requires larger swipes
   - Higher sensitivity (1.0-1.5): Faster adjustments, responds to smaller swipes

2. **Swipe Area**: The default 35% provides good balance

   - Smaller (20-30%): More center area for seeking
   - Larger (40-50%): Easier to trigger volume/brightness

3. **Minimum Distance**: Keep at 10-15 pixels to avoid accidental triggers

4. **Feedback Duration**: 500-800ms provides good visibility without being intrusive

## Troubleshooting

### Gestures Not Working

1. Ensure gestures are enabled in configuration
2. Check that controls are visible (gestures work even when controls are hidden)
3. Verify you're swiping in the correct zones

### Brightness Not Changing (Android)

- Ensure your app has the `WRITE_SETTINGS` permission if needed
- Brightness changes might not work in PiP mode

### Sensitivity Too High/Low

Adjust the sensitivity values:

```dart
gestureConfiguration: BetterPlayerGestureConfiguration(
  volumeSwipeSensitivity: 0.3,      // Slower adjustments
  brightnessSwipeSensitivity: 0.8,  // Faster adjustments
),
```

## Examples

See the included example app at `/example/lib/pages/gesture_controls_page.dart` for a complete implementation.

## Future Enhancements

Potential future improvements:

- [ ] Pinch-to-zoom gesture
- [ ] Double-tap left/right edges to skip (like Netflix)
- [ ] Configurable seek intervals
- [ ] Haptic feedback on gesture detection
- [ ] Custom feedback overlay styling
- [ ] Gesture recording and playback for tutorials

## Contributing

Contributions are welcome! Please submit issues and pull requests for:

- Bug fixes
- Platform-specific improvements
- Additional gesture types
- Enhanced visual feedback options

## License

This feature is part of Better Player Plus and follows the same license.
