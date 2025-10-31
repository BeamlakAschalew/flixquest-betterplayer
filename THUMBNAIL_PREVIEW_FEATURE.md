# Thumbnail Preview Feature

## Overview

Better Player Plus now includes a **thumbnail preview feature** that displays video frames when dragging the seek bar, similar to YouTube and Netflix. This feature provides users with visual feedback about video content at different timestamps.

## Current Implementation

### What Works Now

The current implementation provides **real-time frame preview from buffered content**:

- ✅ Shows actual video frames when hovering/dragging on the seek bar
- ✅ Works for both Material Design and Cupertino (iOS) styles
- ✅ Displays timestamp alongside the thumbnail
- ✅ Smart positioning that stays within screen bounds
- ✅ Smooth, responsive UI with minimal performance impact
- ✅ Zero external dependencies (uses built-in video texture)

### How It Works

1. **User drags** on the progress bar
2. **Player temporarily seeks** to that position
3. **Current video frame** is displayed in a popup thumbnail
4. **Timestamp** shows the exact position
5. **User releases** and video jumps to selected position

### Limitations

⚠️ **Important**: The current implementation can only show frames from **buffered content**.

**Example scenario:**

- Video duration: 30 minutes
- Current position: 10 minutes
- Buffered up to: 12 minutes
- **Preview works**: From 0:00 to 12:00 ✅
- **Preview doesn't work**: From 12:01 to 30:00 ❌

This is a technical limitation of using a single video player instance - it can only display frames that have been downloaded and buffered.

## Usage

### Basic Usage

Enable thumbnail preview in your Better Player configuration:

```dart
BetterPlayerController(
  BetterPlayerConfiguration(
    controlsConfiguration: BetterPlayerControlsConfiguration(
      enableThumbnailPreview: true, // Default is true
    ),
  ),
);
```

### Disable Thumbnail Preview

If you want to disable the feature:

```dart
BetterPlayerConfiguration(
  controlsConfiguration: BetterPlayerControlsConfiguration(
    enableThumbnailPreview: false, // Disable feature
  ),
)
```

### Complete Example

```dart
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';

class VideoPlayerScreen extends StatefulWidget {
  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late BetterPlayerController _betterPlayerController;

  @override
  void initState() {
    super.initState();

    BetterPlayerDataSource dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
    );

    _betterPlayerController = BetterPlayerController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enableThumbnailPreview: true, // Enable thumbnail preview
        ),
        aspectRatio: 16 / 9,
        autoPlay: true,
      ),
      betterPlayerDataSource: dataSource,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Video Player')),
      body: Center(
        child: BetterPlayer(controller: _betterPlayerController),
      ),
    );
  }

  @override
  void dispose() {
    _betterPlayerController.dispose();
    super.dispose();
  }
}
```

## Visual Design

The thumbnail preview includes:

- **Thumbnail**: 120x80 pixels video frame
- **Border**: White border with subtle transparency
- **Shadow**: Drop shadow for depth
- **Timestamp**: HH:MM:SS or MM:SS format
- **Rounded corners**: Modern, polished appearance

## Upgrade to Full YouTube-Like Experience

For **unbuffered frame preview** (showing any frame at any time, even if not downloaded), you need server-side thumbnail generation. See the complete guide:

📖 **[THUMBNAIL_GENERATION_GUIDE.md](./THUMBNAIL_GENERATION_GUIDE.md)**

This advanced implementation requires:

- Node.js/Express backend
- FFmpeg for video processing
- Thumbnail sprite sheet generation
- WebVTT metadata files
- Additional Flutter integration

### Why Server-Side is Required

**Current approach (real-time):**

```
User drags → Player seeks → Shows current frame ✅ (buffered only)
```

**Server-side approach (sprite-based):**

```
Video uploaded → Generate sprite sheet → Store thumbnails
User drags → Load from sprite → Shows any frame ✅ (all positions)
```

Major platforms (YouTube, Netflix, Vimeo) all use sprite-based thumbnails because:

1. **Works for unbuffered content** - No need to download video to see frames
2. **Faster response** - Thumbnails are pre-generated and cached
3. **Lower bandwidth** - One sprite download vs multiple video seeks
4. **Better UX** - Instant preview at any position

## Technical Details

### Modified Files

The thumbnail preview feature modifies these files:

1. **lib/src/controls/better_player_material_progress_bar.dart**

   - Added `_ThumbnailPreviewWidget`
   - Added `_buildThumbnailPreview()` method
   - Added drag position tracking

2. **lib/src/controls/better_player_cupertino_progress_bar.dart**

   - Same changes for iOS-style controls

3. **lib/src/configuration/better_player_controls_configuration.dart**

   - Added `enableThumbnailPreview` configuration option

4. **lib/src/controls/better_player_material_controls.dart**

   - Passes configuration to progress bar

5. **lib/src/controls/better_player_cupertino_controls.dart**
   - Passes configuration to progress bar

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User Interaction                          │
├─────────────────────────────────────────────────────────────┤
│  1. User starts dragging on seek bar                        │
│  2. GestureDetector captures drag position                  │
│  3. Calculate relative position (0.0 to 1.0)                │
│  4. Convert to Duration based on video length               │
│  5. Temporarily seek VideoPlayerController                  │
│  6. Display current frame in _ThumbnailPreviewWidget        │
│  7. Show timestamp overlay                                  │
│  8. Position thumbnail near cursor (with bounds checking)   │
│  9. User releases → Final seek to position                  │
└─────────────────────────────────────────────────────────────┘
```

### Performance Considerations

- **Minimal overhead**: Uses existing video texture, no additional decoding
- **Buffered content only**: Cannot show frames that aren't downloaded
- **Smooth seeking**: Temporary seeks don't interrupt playback buffer
- **Efficient rendering**: Single widget update per drag move
- **Memory efficient**: No frame caching or additional storage

## Browser/Platform Support

The thumbnail preview feature works on all platforms supported by Better Player Plus:

- ✅ Android
- ✅ iOS
- ✅ Web (with limitations on some browsers)
- ✅ Desktop (Windows, macOS, Linux)

## Troubleshooting

### Thumbnail doesn't appear

**Check:**

1. Is `enableThumbnailPreview` set to `true`?
2. Is the video properly initialized?
3. Are you dragging on a buffered region?

### Thumbnail shows black frame

**Possible reasons:**

1. Position is beyond buffered content
2. Video hasn't loaded that frame yet
3. Video codec/format issue

**Solution:** Wait for more content to buffer, or implement server-side sprites

### Thumbnail positioning is off

**Check:**

1. Screen orientation changes
2. Different screen sizes
3. Custom controls layout

**Solution:** The feature includes smart bounds checking, but custom layouts may need adjustments

## Future Enhancements

Potential improvements for future versions:

1. **Adaptive thumbnail size** - Scale based on screen size
2. **Configurable thumbnail dimensions** - Let developers customize size
3. **Custom styling** - Allow style overrides
4. **Gesture improvements** - Better touch feedback
5. **Built-in sprite support** - Native sprite sheet handling
6. **Progressive loading** - Load sprite chunks on demand

## Contributing

If you want to enhance the thumbnail preview feature:

1. Test thoroughly on multiple devices
2. Consider performance impact
3. Maintain backwards compatibility
4. Update documentation
5. Add examples for new features

## License

This feature is part of Better Player Plus and follows the same license (Apache 2.0).

## Credits

- Inspired by YouTube, Netflix, and Vimeo video players
- Built on top of Better Player by Jakub Homlala
- Enhanced by the Better Player Plus community

## Support

For issues or questions:

- Open an issue on GitHub
- Check existing issues for solutions
- Refer to the main README for general Better Player Plus help

---

**Need unbuffered frame preview?** → See [THUMBNAIL_GENERATION_GUIDE.md](./THUMBNAIL_GENERATION_GUIDE.md)
