# Better Player Plus (FlixQuest Edition)

<p align="center">
  <strong>Advanced video player for Flutter with AndroidX Media3, Swift iOS backend, gesture controls, seek thumbnail previews, and dedicated Android TV support.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-%3E%3D3.35.0-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-%3E%3D3.9.0-0175C2?logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Android%20Media3-1.8.0-3DDC84?logo=android&logoColor=white" alt="Android Media3">
  <img src="https://img.shields.io/badge/iOS-Swift-F05138?logo=swift&logoColor=white" alt="iOS Swift">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Android%20TV-blue" alt="Platform">
  <img src="https://img.shields.io/badge/License-Apache%202.0-green.svg" alt="License">
</p>

---

## ✨ Key Enhancements & Features

### 📺 Android TV (10-Foot UI Experience)
- **D-Pad Focus Navigation**: Full remote control support with directional focus nodes and focus memory.
- **TV Media Controls & Menus**: Specially designed TV progress bar, timeline editing, audio/subtitle selectors, and quick settings menu.
- **Back Dispatcher & Dialogs**: Seamless handling of TV back events and overlay menus.

### 👆 Gesture-Based Touch Controls
- **Volume Control**: Vertical swipe on the right 35% of the screen with animated percentage HUD.
- **Brightness Control**: Vertical swipe on the left 35% of the screen using native Android & iOS brightness APIs.
- **Seek Scrubbing**: Horizontal swipe in the center 30% for smooth forward/rewind seeking with seconds feedback.
- **Customizable Sensitivity**: Adjust swipe sensitivity and zone boundaries per gesture.

### 🖼️ Seek Bar Thumbnail Previews
- **Real-Time Frame Preview**: Instant video frame thumbnail preview when scrubbing the seek bar.
- **Smart Bounds Positioning**: Automatically positions preview tooltips within screen edges.
- **Sprite Sheet & WebVTT Support**: Built-in architecture for loading server-side sprite thumbnails for unbuffered preview.

### ⚡ Modern Native Engine
- **Android**: Fully migrated to **AndroidX Media3 1.8.0 (ExoPlayer)** with low-memory buffering optimizations and cache management.
- **iOS**: Fully rewritten in modern **Swift** with iOS 13+ compatibility and native brightness integration.

### 🎨 Refined UI with Phosphor Icons
- Cohesive, modern player controls using **Phosphor Icons** for Material, Cupertino, and TV interfaces.

---

## 📋 Complete Feature List

- ✔️ **Adaptive Streaming**: Full HLS (`.m3u8`) and DASH (`.mpd`) adaptive bitrate switching.
- ✔️ **Audio & Video Tracks**: Dynamic selection of multi-language audio streams and video resolutions.
- ✔️ **Subtitles Support**: SRT, WebVTT (with HTML styling), segmented HLS subtitles, memory sources, and custom styling (size, color, background).
- ✔️ **Picture-in-Picture (PiP)**: Background video playback and native PiP support on Android & iOS.
- ✔️ **DRM Support**: Widevine, FairPlay (EZDRM), and ClearKey integration.
- ✔️ **Caching & Performance**: Video cache clearing, configurable buffer duration, and low-memory device tuning.
- ✔️ **Custom Headers & Proxy**: Pass custom HTTP headers and user-agent strings to media streams.
- ✔️ **Notification Controls**: System notification media controls and lock screen playback controls.
- ✔️ **Aspect Ratio & BoxFit**: Flexible video scaling and fill modes.

---

## 💻 Installation

Add the dependency to your `pubspec.yaml`:

### Via Git Repository (Recommended):
```yaml
dependencies:
  better_player_plus:
    git:
      url: https://github.com/BeamlakAschalew/flixquest-betterplayer.git
```

### Via Local Path:
```yaml
dependencies:
  better_player_plus:
    path: ../flixquest-betterplayer
```

Import the package:
```dart
import 'package:better_player_plus/better_player_plus.dart';
```

---

## 🚀 Quick Start

### Basic Video Player

```dart
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late BetterPlayerController _controller;

  @override
  void initState() {
    super.initState();
    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    );

    _controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        aspectRatio: 16 / 9,
        autoPlay: true,
        allowedScreenSleep: false,
      ),
      betterPlayerDataSource: dataSource,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: BetterPlayer(controller: _controller),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

---

## ⚙️ Feature Configuration Examples

### 1. Enabling Gesture Controls

```dart
final playerConfig = BetterPlayerConfiguration(
  controlsConfiguration: BetterPlayerControlsConfiguration(
    gestureConfiguration: const BetterPlayerGestureConfiguration(
      enableVolumeSwipe: true,
      enableBrightnessSwipe: true,
      enableSeekSwipe: true,
      volumeSwipeSensitivity: 0.5,
      brightnessSwipeSensitivity: 0.5,
      seekSwipeSensitivity: 1.0,
      swipeFeedbackDuration: Duration(milliseconds: 500),
    ),
  ),
);
```

### 2. Enabling Seek Thumbnail Previews

```dart
final playerConfig = BetterPlayerConfiguration(
  controlsConfiguration: const BetterPlayerControlsConfiguration(
    enableThumbnailPreview: true,
  ),
);
```

### 3. Dedicated Android TV Controls

For Android TV apps, use `BetterPlayerTvControls` with directional D-Pad handling:

```dart
BetterPlayerTvControls(
  controller: betterPlayerController,
  accentColor: Theme.of(context).colorScheme.primary,
  onControlsVisibilityChanged: (visible) {
    // Handle UI overlay changes
  },
  onExit: () {
    Navigator.of(context).pop();
  },
)
```

### 4. Custom Subtitle Sources (Memory / External)

```dart
final subtitleSource = BetterPlayerSubtitlesSource(
  type: BetterPlayerSubtitlesSourceType.memory,
  name: 'English (Custom)',
  content: srtOrVttStringContent,
  selectedByDefault: true,
);

controller.setupSubtitleSource(subtitleSource);
```

---

## 📖 In-Depth Guides

- 📖 **[Gesture Controls Guide](GESTURE_CONTROLS.md)**: Detailed documentation of swipe zones, sensitivity settings, and visual feedback overlays.
- 📖 **[Thumbnail Preview Feature](THUMBNAIL_PREVIEW_FEATURE.md)**: How real-time buffered frame previews work.
- 📖 **[Server-Side Thumbnail Sprites Guide](THUMBNAIL_GENERATION_GUIDE.md)**: Tutorial for generating and loading WebVTT sprite sheets for unbuffered scrub previews.
- 📖 **[Implementation Summary](IMPLEMENTATION_SUMMARY.md)**: Architecture notes and platform bridge details.

---

## 📱 Platform Support

| Feature | Android | iOS | Android TV |
| --- | :---: | :---: | :---: |
| **Engine** | AndroidX Media3 (1.8.0) | AVPlayer (Swift) | AndroidX Media3 (1.8.0) |
| **HLS / DASH** | ✅ | ✅ | ✅ |
| **Gesture Controls** | ✅ | ✅ | N/A (D-Pad) |
| **Brightness Gesture** | ✅ | ✅ | N/A |
| **Thumbnail Preview** | ✅ | ✅ | ✅ |
| **D-Pad TV Controls** | N/A | N/A | ✅ |
| **Picture-in-Picture** | ✅ | ✅ | ⚠️ |
| **DRM Support** | Widevine / ClearKey | FairPlay (EZDRM) | Widevine / ClearKey |

---

## 🤝 Contributing

Contributions, bug fixes, and improvements are welcome! Please open an issue or submit a pull request on the repository.

---

## 📄 License

This project is licensed under the **Apache License 2.0** - see the [`LICENSE`](LICENSE) file for details.

---

### 🙏 Credits

- Built upon the foundations of **Better Player** by [Jakub Homlala](https://github.com/jhomlala/betterplayer) and **Chewie**.
- Enhanced and maintained for the **FlixQuest** ecosystem.
