# Better Player Plus

[![Pub](https://img.shields.io/pub/v/better_player_plus.svg)](https://pub.dev/packages/better_player_plus)
[![License](https://img.shields.io/github/license/SunnatilloShavkatov/betterplayer.svg?style=flat)](https://github.com/SunnatilloShavkatov/betterplayer)
[![Platform](https://img.shields.io/badge/platform-flutter-blue.svg)](https://flutter.dev)

Advanced video player for Flutter, based on `video_player` and inspired by Chewie and Better Player. It solves many common use cases out of the box and is easy to integrate.

<table>
  <tr>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/1.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/2.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/3.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/4.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/5.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/6.png"></td>
  </tr>
  <tr>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/7.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/8.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/9.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/10.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/11.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/12.png"></td>
  </tr>
  <tr>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/13.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/14.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/15.png"></td>
    <td><img width="250px" src="https://raw.githubusercontent.com/jhomlala/betterplayer/master/media/16.png"></td>
  </tr>
</table>

### Features
- ✔️ Fixed common playback bugs
- ✔️ Advanced configuration options
- ✔️ Refactored, customizable player controls (Material & Cupertino)
- ✔️ Playlists
- ✔️ ListView/feeds autoplay support
- ✔️ Subtitles: SRT, WebVTT (HTML tags), HLS subtitles, multiple tracks
- ✔️ HTTP headers support
- ✔️ BoxFit for video
- ✔️ Playback speed control
- ✔️ HLS (tracks, segmented subtitles, audio tracks)
- ✔️ DASH (tracks, subtitles, audio tracks)
- ✔️ Alternate resolutions
- ✔️ Caching
- ✔️ Notifications
- ✔️ Picture-in-Picture
- ✔️ DRM (token, Widevine, FairPlay via EZDRM)

### Installation
Add the dependency in your `pubspec.yaml`:

```yaml
dependencies:
  better_player_plus: ^1.1.2
```

Import the package:

```dart
import 'package:better_player_plus/better_player_plus.dart';
```

### Quick start
Minimal example showing a network source:

```dart
final dataSource = BetterPlayerDataSource(
  BetterPlayerDataSourceType.network,
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
);

final controller = BetterPlayerController(
  const BetterPlayerConfiguration(),
  betterPlayerDataSource: dataSource,
);

// In your widget tree
BetterPlayer(controller: controller);
```

### Documentation
- Installation notes: [`doc/install.md`](doc/install.md)
- Example application: [`example/`](example/)

### Important information
This package is actively evolving. Breaking changes may appear between versions. Contributions are welcome — please open issues or pull requests.

### License
Apache 2.0 — see [`LICENSE`](LICENSE).

### Recent Updates (v1.1.2)
- **Code Quality Improvements**: Fixed missing type annotations and improved static analysis compliance
- **Project Metadata**: Updated iOS podspec with proper project information and version consistency
- **Dependency Management**: Fixed example app dependency version constraints for better stability
- **Documentation**: Enhanced project documentation and version consistency across all files

### Previous Updates (v1.1.1)
- **iOS Migration**: Complete migration from Objective-C to Swift for better maintainability and modern iOS development practices
- **Android Media3 1.8.0**: Full migration to the latest Android Media3 player with enhanced performance and features
- **Deprecated API Fixes**: Removed deprecated GLKit dependency and updated UIApplication.keyWindow usage
- **Improved Compatibility**: Enhanced iOS 13+ support with proper backward compatibility

### Credits
This work builds on the great foundations of Chewie and the original Better Player. Thanks to all contributors of those projects.

**Special Thanks**: This project benefited greatly from Cursor AI assistance during the iOS Objective-C to Swift migration process.
