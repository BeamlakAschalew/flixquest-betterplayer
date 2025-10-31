# Quick Start: Integrating Server-Side Thumbnails

This is a quick reference for integrating server-side thumbnail generation with Better Player Plus. For complete details, see [THUMBNAIL_GENERATION_GUIDE.md](./THUMBNAIL_GENERATION_GUIDE.md).

## Overview

```
Current Feature:    Shows frames from buffered content only
Server-Side Addon:  Shows frames from ANY position (even unbuffered)
```

## What You Need

### Backend (Node.js)

1. Express server for video upload
2. FFmpeg for thumbnail generation
3. Sprite sheet + VTT file generation

### Flutter (Client)

1. Model class for sprite metadata
2. Widget to display sprite-based thumbnails
3. HTTP client to upload videos

## 5-Minute Setup

### Step 1: Set Up Node.js Server

```bash
mkdir video-thumbnail-server
cd video-thumbnail-server
npm init -y
npm install express multer fluent-ffmpeg cors
```

Create `server.js` (simplified version):

```javascript
const express = require("express");
const multer = require("multer");
const ffmpeg = require("fluent-ffmpeg");
const path = require("path");

const app = express();
const upload = multer({ dest: "uploads/videos/" });

app.use("/thumbnails", express.static("uploads/thumbnails"));
app.use("/videos", express.static("uploads/videos"));

app.post("/upload", upload.single("video"), async (req, res) => {
  const videoPath = req.file.path;
  const spriteOutput = `uploads/thumbnails/${req.file.filename}_sprite.jpg`;

  // Extract frames and create sprite (simplified)
  ffmpeg(videoPath)
    .screenshots({
      count: 60,
      folder: "uploads/thumbnails",
      filename: `${req.file.filename}_sprite.jpg`,
      size: "1600x900", // 10 columns x 6 rows of 160x90 thumbnails
    })
    .on("end", () => {
      res.json({
        videoUrl: `/videos/${req.file.filename}`,
        spriteUrl: `/thumbnails/${req.file.filename}_sprite.jpg`,
        interval: 5,
        width: 160,
        height: 90,
        columns: 10,
        rows: 6,
      });
    });
});

app.listen(3000, () => console.log("Server running on port 3000"));
```

### Step 2: Add Flutter Models

Create `lib/src/models/better_player_thumbnail_sprite.dart`:

```dart
class BetterPlayerThumbnailSprite {
  final String spriteUrl;
  final int interval;
  final int width;
  final int height;
  final int columns;
  final int rows;

  const BetterPlayerThumbnailSprite({
    required this.spriteUrl,
    required this.interval,
    required this.width,
    required this.height,
    required this.columns,
    required this.rows,
  });

  // Get frame coordinates for timestamp
  (int x, int y) getFramePosition(Duration position) {
    final frameIndex = (position.inSeconds / interval).floor();
    final row = frameIndex ~/ columns;
    final col = frameIndex % columns;
    return (col * width, row * height);
  }
}
```

### Step 3: Add to Data Source

Update `better_player_data_source.dart`:

```dart
class BetterPlayerDataSource {
  // ... existing fields
  final BetterPlayerThumbnailSprite? thumbnailSprite;

  BetterPlayerDataSource(
    this.type,
    this.url, {
    // ... existing parameters
    this.thumbnailSprite,
  });
}
```

### Step 4: Use in Your App

```dart
// 1. Upload video and get sprite info
Future<Map<String, dynamic>> uploadVideo(File video) async {
  var request = http.MultipartRequest(
    'POST',
    Uri.parse('http://localhost:3000/upload')
  );
  request.files.add(await http.MultipartFile.fromPath('video', video.path));

  var response = await request.send();
  var responseData = await response.stream.bytesToString();
  return jsonDecode(responseData);
}

// 2. Create data source with sprite
Future<void> playVideo(File videoFile) async {
  final uploadResult = await uploadVideo(videoFile);

  final sprite = BetterPlayerThumbnailSprite(
    spriteUrl: 'http://localhost:3000${uploadResult['spriteUrl']}',
    interval: uploadResult['interval'],
    width: uploadResult['width'],
    height: uploadResult['height'],
    columns: uploadResult['columns'],
    rows: uploadResult['rows'],
  );

  final dataSource = BetterPlayerDataSource(
    BetterPlayerDataSourceType.network,
    'http://localhost:3000${uploadResult['videoUrl']}',
    thumbnailSprite: sprite,
  );

  final controller = BetterPlayerController(
    BetterPlayerConfiguration(
      controlsConfiguration: BetterPlayerControlsConfiguration(
        enableThumbnailPreview: true,
      ),
    ),
    betterPlayerDataSource: dataSource,
  );
}
```

## How It Works

### Without Server-Side (Current)

```
User drags to 28min → Video not buffered → No preview ❌
```

### With Server-Side (Enhanced)

```
Video uploaded → Sprite generated → Stored on server
User drags to 28min → Load from sprite → Preview shown ✅
```

## Sprite Sheet Explained

A sprite sheet is a single image containing multiple frames:

```
┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐
│ 0s │ 5s │ 10s│ 15s│ 20s│ 25s│ 30s│ 35s│ 40s│ 45s│
├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
│ 50s│ 55s│60s │65s │70s │75s │80s │85s │90s │95s │
├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
│100s│105s│... │... │... │... │... │... │... │... │
└────┴────┴────┴────┴────┴────┴────┴────┴────┴────┘
```

When user hovers at 65 seconds:

1. Calculate position: `(65 / 5) = 13th frame`
2. Calculate coordinates: `row = 1, col = 3`
3. Crop from sprite: `x = 3 * 160, y = 1 * 90`
4. Display cropped section

## Production Checklist

- [ ] Install FFmpeg on server
- [ ] Set up file storage (S3, Cloud Storage)
- [ ] Add CDN for sprite delivery
- [ ] Implement background job queue
- [ ] Add upload authentication
- [ ] Configure CORS properly
- [ ] Test with various video formats
- [ ] Monitor processing times
- [ ] Set up error handling
- [ ] Implement cleanup for old files

## Comparison

| Feature                 | Current (Buffered Only)    | Server-Side (Full)       |
| ----------------------- | -------------------------- | ------------------------ |
| Shows buffered frames   | ✅ Yes                     | ✅ Yes                   |
| Shows unbuffered frames | ❌ No                      | ✅ Yes                   |
| Setup complexity        | ✅ Simple (built-in)       | ⚠️ Requires backend      |
| Network usage           | ✅ None (uses video)       | ⚠️ Downloads sprite      |
| Preview speed           | ✅ Instant (buffered)      | ✅ Instant (all)         |
| Storage needed          | ✅ None                    | ⚠️ Sprite files          |
| Best for                | Small videos, good network | Long videos, any network |

## Common Issues

### Sprite not showing

- Check CORS headers on server
- Verify sprite URL is accessible
- Check network tab in DevTools

### Wrong frame displayed

- Verify interval calculation
- Check sprite dimensions match metadata
- Ensure frames are in correct order

### Slow generation

- Reduce frame count (increase interval)
- Lower thumbnail resolution
- Use background job queue

## Next Steps

1. **Test locally** with the simplified server above
2. **See full implementation** in [THUMBNAIL_GENERATION_GUIDE.md](./THUMBNAIL_GENERATION_GUIDE.md)
3. **Customize** interval, size, quality for your needs
4. **Deploy** to production with proper infrastructure

## Resources

- **Full Guide**: [THUMBNAIL_GENERATION_GUIDE.md](./THUMBNAIL_GENERATION_GUIDE.md)
- **Feature Docs**: [THUMBNAIL_PREVIEW_FEATURE.md](./THUMBNAIL_PREVIEW_FEATURE.md)
- **FFmpeg Docs**: https://ffmpeg.org/documentation.html
- **WebVTT Spec**: https://www.w3.org/TR/webvtt1/

## Support

Questions? Check the full documentation or open an issue on GitHub!
