# Server-Side Thumbnail Generation Guide

## Overview

This guide explains how to implement YouTube-like thumbnail preview generation using Node.js and Express, and integrate it with Better Player Plus for unbuffered frame previews.

The current implementation shows real-time frames from buffered content. To show frames from unbuffered positions (e.g., minute 28 when only 12 minutes are buffered), you need server-side thumbnail generation.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Video Upload Flow                        │
├─────────────────────────────────────────────────────────────┤
│  1. User uploads video                                       │
│  2. Server processes video with FFmpeg                       │
│  3. Generate thumbnail sprite sheet (e.g., one frame/5sec)  │
│  4. Generate VTT file (WebVTT) with frame coordinates       │
│  5. Store sprite + VTT alongside video                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                     Playback Flow                            │
├─────────────────────────────────────────────────────────────┤
│  1. Flutter app loads video metadata                        │
│  2. Download sprite sheet + VTT file                        │
│  3. On seek bar hover: calculate which frame to show        │
│  4. Display cropped section of sprite sheet                 │
└─────────────────────────────────────────────────────────────┘
```

## Part 1: Node.js/Express Server Implementation

### Prerequisites

```bash
npm install express multer fluent-ffmpeg
npm install --save-dev @types/express @types/multer @types/fluent-ffmpeg
```

You also need FFmpeg installed on your server:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install ffmpeg

# macOS
brew install ffmpeg

# Windows
# Download from https://ffmpeg.org/download.html
```

### Server Implementation

#### 1. Project Structure

```
video-thumbnail-server/
├── server.js (or server.ts)
├── routes/
│   ├── upload.js
│   └── video.js
├── services/
│   ├── thumbnailGenerator.js
│   └── vttGenerator.js
├── uploads/
│   ├── videos/
│   ├── thumbnails/
│   └── vtt/
├── package.json
└── .env
```

#### 2. Thumbnail Generator Service (`services/thumbnailGenerator.js`)

```javascript
const ffmpeg = require("fluent-ffmpeg");
const path = require("path");
const fs = require("fs").promises;

class ThumbnailGenerator {
  /**
   * Generate thumbnail sprite sheet from video
   * @param {string} videoPath - Path to input video file
   * @param {object} options - Generation options
   * @returns {Promise<object>} - Sprite sheet metadata
   */
  async generateSprite(videoPath, options = {}) {
    const {
      outputDir = "./uploads/thumbnails",
      interval = 5, // Extract frame every 5 seconds
      width = 160, // Thumbnail width
      height = 90, // Thumbnail height
      columns = 10, // Thumbnails per row in sprite
    } = options;

    // Get video duration first
    const duration = await this.getVideoDuration(videoPath);
    const totalFrames = Math.floor(duration / interval);
    const rows = Math.ceil(totalFrames / columns);

    const videoId = path.basename(videoPath, path.extname(videoPath));
    const spriteFileName = `${videoId}_sprite.jpg`;
    const spritePath = path.join(outputDir, spriteFileName);
    const tempDir = path.join(outputDir, `temp_${videoId}`);

    try {
      // Create temp directory for individual frames
      await fs.mkdir(tempDir, { recursive: true });
      await fs.mkdir(outputDir, { recursive: true });

      // Extract frames at intervals
      await this.extractFrames(videoPath, tempDir, interval, width, height);

      // Combine frames into sprite sheet
      await this.createSpriteSheet(
        tempDir,
        spritePath,
        columns,
        rows,
        width,
        height
      );

      // Clean up temp frames
      await fs.rm(tempDir, { recursive: true, force: true });

      return {
        spriteUrl: `/thumbnails/${spriteFileName}`,
        interval,
        width,
        height,
        columns,
        rows,
        totalFrames,
        duration,
      };
    } catch (error) {
      // Clean up on error
      await fs.rm(tempDir, { recursive: true, force: true }).catch(() => {});
      throw error;
    }
  }

  /**
   * Get video duration in seconds
   */
  getVideoDuration(videoPath) {
    return new Promise((resolve, reject) => {
      ffmpeg.ffprobe(videoPath, (err, metadata) => {
        if (err) return reject(err);
        resolve(metadata.format.duration);
      });
    });
  }

  /**
   * Extract frames from video at regular intervals
   */
  extractFrames(videoPath, outputDir, interval, width, height) {
    return new Promise((resolve, reject) => {
      ffmpeg(videoPath)
        .outputOptions([
          `-vf fps=1/${interval},scale=${width}:${height}:force_original_aspect_ratio=decrease,pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2`,
        ])
        .output(path.join(outputDir, "frame_%04d.jpg"))
        .on("end", resolve)
        .on("error", reject)
        .run();
    });
  }

  /**
   * Combine individual frames into a sprite sheet using ImageMagick/ffmpeg
   */
  async createSpriteSheet(framesDir, outputPath, columns, rows, width, height) {
    const frames = await fs.readdir(framesDir);
    const sortedFrames = frames
      .filter((f) => f.startsWith("frame_"))
      .sort()
      .map((f) => path.join(framesDir, f));

    return new Promise((resolve, reject) => {
      // Use ffmpeg to create sprite sheet
      const filterComplex = this.buildTileFilter(
        sortedFrames.length,
        columns,
        rows
      );

      const command = ffmpeg();
      sortedFrames.forEach((frame) => command.input(frame));

      command
        .complexFilter(filterComplex)
        .outputOptions("-q:v", "2") // JPEG quality
        .output(outputPath)
        .on("end", resolve)
        .on("error", reject)
        .run();
    });
  }

  /**
   * Build FFmpeg tile filter for sprite sheet
   */
  buildTileFilter(frameCount, columns, rows) {
    // Create a grid layout of thumbnails
    // This is a simplified version - you may need to adjust based on your needs
    let filter = "";
    for (let i = 0; i < frameCount; i++) {
      filter += `[${i}:v]`;
    }
    filter += `xstack=inputs=${frameCount}:layout=`;

    const positions = [];
    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < columns; col++) {
        const index = row * columns + col;
        if (index >= frameCount) break;
        positions.push(`${col}_${row}`);
      }
    }
    filter += positions.join("|");

    return filter;
  }
}

module.exports = new ThumbnailGenerator();
```

#### 3. VTT Generator Service (`services/vttGenerator.js`)

```javascript
const fs = require("fs").promises;
const path = require("path");

class VTTGenerator {
  /**
   * Generate WebVTT file with thumbnail coordinates
   * @param {object} spriteMetadata - Sprite sheet metadata
   * @param {string} outputDir - Output directory for VTT file
   * @returns {Promise<string>} - Path to VTT file
   */
  async generateVTT(spriteMetadata, outputDir = "./uploads/vtt") {
    const {
      spriteUrl,
      interval,
      width,
      height,
      columns,
      totalFrames,
      duration,
    } = spriteMetadata;

    await fs.mkdir(outputDir, { recursive: true });

    const videoId = path.basename(spriteUrl, "_sprite.jpg");
    const vttFileName = `${videoId}_thumbnails.vtt`;
    const vttPath = path.join(outputDir, vttFileName);

    let vttContent = "WEBVTT\n\n";

    for (let i = 0; i < totalFrames; i++) {
      const startTime = i * interval;
      const endTime = Math.min((i + 1) * interval, duration);

      const row = Math.floor(i / columns);
      const col = i % columns;
      const x = col * width;
      const y = row * height;

      vttContent += this.formatVTTCue(
        startTime,
        endTime,
        spriteUrl,
        x,
        y,
        width,
        height
      );
    }

    await fs.writeFile(vttPath, vttContent);

    return {
      vttUrl: `/vtt/${vttFileName}`,
      vttPath,
    };
  }

  /**
   * Format a WebVTT cue with thumbnail coordinates
   */
  formatVTTCue(startTime, endTime, spriteUrl, x, y, width, height) {
    const formatTime = (seconds) => {
      const h = Math.floor(seconds / 3600);
      const m = Math.floor((seconds % 3600) / 60);
      const s = Math.floor(seconds % 60);
      const ms = Math.floor((seconds % 1) * 1000);
      return `${String(h).padStart(2, "0")}:${String(m).padStart(
        2,
        "0"
      )}:${String(s).padStart(2, "0")}.${String(ms).padStart(3, "0")}`;
    };

    return `${formatTime(startTime)} --> ${formatTime(
      endTime
    )}\n${spriteUrl}#xywh=${x},${y},${width},${height}\n\n`;
  }
}

module.exports = new VTTGenerator();
```

#### 4. Upload Route (`routes/upload.js`)

```javascript
const express = require("express");
const multer = require("multer");
const path = require("path");
const thumbnailGenerator = require("../services/thumbnailGenerator");
const vttGenerator = require("../services/vttGenerator");

const router = express.Router();

// Configure multer for video uploads
const storage = multer.diskStorage({
  destination: "./uploads/videos/",
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + "-" + Math.round(Math.random() * 1e9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 500 * 1024 * 1024 }, // 500MB limit
  fileFilter: (req, file, cb) => {
    const allowedTypes = /mp4|mkv|avi|mov|webm/;
    const extname = allowedTypes.test(
      path.extname(file.originalname).toLowerCase()
    );
    const mimetype = allowedTypes.test(file.mimetype);

    if (mimetype && extname) {
      return cb(null, true);
    }
    cb(new Error("Only video files are allowed!"));
  },
});

/**
 * POST /api/upload/video
 * Upload video and generate thumbnails
 */
router.post("/video", upload.single("video"), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: "No video file uploaded" });
    }

    const videoPath = req.file.path;
    const videoUrl = `/videos/${req.file.filename}`;

    // Generate thumbnail sprite sheet
    console.log("Generating thumbnail sprite...");
    const spriteMetadata = await thumbnailGenerator.generateSprite(videoPath, {
      interval: req.body.interval ? parseInt(req.body.interval) : 5,
      width: req.body.thumbnailWidth ? parseInt(req.body.thumbnailWidth) : 160,
      height: req.body.thumbnailHeight
        ? parseInt(req.body.thumbnailHeight)
        : 90,
      columns: req.body.columns ? parseInt(req.body.columns) : 10,
    });

    // Generate VTT file
    console.log("Generating VTT file...");
    const vttData = await vttGenerator.generateVTT(spriteMetadata);

    // Return video metadata
    res.json({
      success: true,
      video: {
        url: videoUrl,
        filename: req.file.filename,
        size: req.file.size,
        duration: spriteMetadata.duration,
      },
      thumbnails: {
        spriteUrl: spriteMetadata.spriteUrl,
        vttUrl: vttData.vttUrl,
        interval: spriteMetadata.interval,
        width: spriteMetadata.width,
        height: spriteMetadata.height,
        columns: spriteMetadata.columns,
        rows: spriteMetadata.rows,
        totalFrames: spriteMetadata.totalFrames,
      },
    });
  } catch (error) {
    console.error("Upload error:", error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
```

#### 5. Main Server (`server.js`)

```javascript
const express = require("express");
const cors = require("cors");
const path = require("path");
const uploadRoute = require("./routes/upload");

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Serve static files
app.use("/videos", express.static(path.join(__dirname, "uploads/videos")));
app.use(
  "/thumbnails",
  express.static(path.join(__dirname, "uploads/thumbnails"))
);
app.use("/vtt", express.static(path.join(__dirname, "uploads/vtt")));

// Routes
app.use("/api/upload", uploadRoute);

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// Error handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: err.message || "Internal server error" });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Upload endpoint: http://localhost:${PORT}/api/upload/video`);
});
```

#### 6. Package.json

```json
{
  "name": "video-thumbnail-server",
  "version": "1.0.0",
  "description": "Video thumbnail generation server for Better Player Plus",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "multer": "^1.4.5-lts.1",
    "fluent-ffmpeg": "^2.1.2",
    "cors": "^2.8.5",
    "dotenv": "^16.0.3"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
```

## Part 2: Flutter Integration with Better Player Plus

### 1. Add Dependencies to `pubspec.yaml`

```yaml
dependencies:
  http: ^1.1.0
  cached_network_image: ^3.3.0
```

### 2. Create Thumbnail Sprite Data Model

Create `lib/src/models/better_player_thumbnail_sprite.dart`:

```dart
/// Model representing thumbnail sprite metadata from server
class BetterPlayerThumbnailSprite {
  final String spriteUrl;
  final String vttUrl;
  final int interval; // seconds between frames
  final int width;
  final int height;
  final int columns;
  final int rows;
  final int totalFrames;

  const BetterPlayerThumbnailSprite({
    required this.spriteUrl,
    required this.vttUrl,
    required this.interval,
    required this.width,
    required this.height,
    required this.columns,
    required this.rows,
    required this.totalFrames,
  });

  factory BetterPlayerThumbnailSprite.fromJson(Map<String, dynamic> json) {
    return BetterPlayerThumbnailSprite(
      spriteUrl: json['spriteUrl'] as String,
      vttUrl: json['vttUrl'] as String,
      interval: json['interval'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
      columns: json['columns'] as int,
      rows: json['rows'] as int,
      totalFrames: json['totalFrames'] as int,
    );
  }

  /// Get frame coordinates for a specific timestamp
  SpriteFrameCoordinates getFrameCoordinates(Duration position) {
    final frameIndex = (position.inSeconds / interval).floor();
    if (frameIndex >= totalFrames) {
      return SpriteFrameCoordinates(
        x: 0,
        y: 0,
        width: width,
        height: height,
      );
    }

    final row = frameIndex ~/ columns;
    final col = frameIndex % columns;

    return SpriteFrameCoordinates(
      x: col * width,
      y: row * height,
      width: width,
      height: height,
    );
  }
}

class SpriteFrameCoordinates {
  final int x;
  final int y;
  final int width;
  final int height;

  const SpriteFrameCoordinates({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}
```

### 3. Add Sprite Configuration to Data Source

Modify `lib/src/configuration/better_player_data_source.dart`:

```dart
// Add this field to BetterPlayerDataSource class
final BetterPlayerThumbnailSprite? thumbnailSprite;

// Update constructor
BetterPlayerDataSource({
  // ... existing parameters
  this.thumbnailSprite,
});
```

### 4. Update Progress Bar with Sprite Support

Modify `lib/src/controls/better_player_material_progress_bar.dart`:

Add this new widget for sprite-based thumbnails:

```dart
/// Widget that displays thumbnail from sprite sheet
class _SpriteThumbnailPreviewWidget extends StatelessWidget {
  const _SpriteThumbnailPreviewWidget({
    required this.sprite,
    required this.position,
    required this.width,
    required this.height,
  });

  final BetterPlayerThumbnailSprite sprite;
  final Duration position;
  final double width;
  final double height;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final coordinates = sprite.getFrameCoordinates(position);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sprite frame preview
          Container(
            width: width,
            height: height,
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(6.0)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6.0)),
              child: CachedNetworkImage(
                imageUrl: sprite.spriteUrl,
                imageBuilder: (context, imageProvider) {
                  return FittedBox(
                    fit: BoxFit.cover,
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topLeft,
                        widthFactor: sprite.width.toDouble() / (sprite.columns * sprite.width),
                        heightFactor: sprite.height.toDouble() / (sprite.rows * sprite.height),
                        child: Transform.translate(
                          offset: Offset(-coordinates.x.toDouble(), -coordinates.y.toDouble()),
                          child: Image(
                            image: imageProvider,
                            width: (sprite.columns * sprite.width).toDouble(),
                            height: (sprite.rows * sprite.height).toDouble(),
                            fit: BoxFit.none,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Icon(
                    Icons.videocam_outlined,
                    color: Colors.white.withOpacity(0.5),
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
          // Timestamp
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(6.0)),
            ),
            child: Text(
              _formatDuration(position),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Update the `_buildThumbnailPreview` method in `_VideoProgressBarState`:

```dart
Widget? _buildThumbnailPreview() {
  if (!widget.enableThumbnailPreview ||
      controller == null ||
      !controller!.value.initialized ||
      _dragPositionForThumbnail == null) {
    return null;
  }

  final duration = controller!.value.duration;
  if (duration == null) return null;

  final seekPosition = Duration(
    milliseconds: (duration.inMilliseconds * _dragPositionForThumbnail!).round(),
  );

  // Check if sprite is available
  final sprite = widget.betterPlayerController?.betterPlayerDataSource?.thumbnailSprite;

  const thumbnailWidth = 120.0;
  const thumbnailHeight = 80.0;

  Widget thumbnailWidget;

  if (sprite != null) {
    // Use sprite-based thumbnail (works for unbuffered content)
    thumbnailWidget = _SpriteThumbnailPreviewWidget(
      sprite: sprite,
      position: seekPosition,
      width: thumbnailWidth,
      height: thumbnailHeight,
    );
  } else {
    // Fall back to real-time thumbnail (only buffered content)
    thumbnailWidget = _ThumbnailPreviewWidget(
      controller: controller!,
      position: seekPosition,
      width: thumbnailWidth,
      height: thumbnailHeight,
    );
  }

  // Position calculation remains the same...
  final screenWidth = MediaQuery.of(context).size.width;
  final progressBarWidth = screenWidth - 32;
  final thumbnailX = (progressBarWidth * _dragPositionForThumbnail!) - (thumbnailWidth / 2);

  final clampedX = thumbnailX.clamp(8.0, screenWidth - thumbnailWidth - 8.0);

  return Positioned(
    left: clampedX,
    bottom: 40,
    child: thumbnailWidget,
  );
}
```

### 5. Usage Example

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

// Upload video and get sprite metadata
Future<BetterPlayerThumbnailSprite?> uploadVideoAndGetSprite(File videoFile) async {
  final uri = Uri.parse('http://your-server.com/api/upload/video');
  final request = http.MultipartRequest('POST', uri);

  request.files.add(await http.MultipartFile.fromPath('video', videoFile.path));
  request.fields['interval'] = '5'; // Frame every 5 seconds
  request.fields['thumbnailWidth'] = '160';
  request.fields['thumbnailHeight'] = '90';
  request.fields['columns'] = '10';

  final response = await request.send();

  if (response.statusCode == 200) {
    final responseData = await response.stream.bytesToString();
    final json = jsonDecode(responseData);

    return BetterPlayerThumbnailSprite.fromJson(json['thumbnails']);
  }

  return null;
}

// Use with Better Player
void playVideoWithSprite() async {
  final sprite = await uploadVideoAndGetSprite(myVideoFile);

  final betterPlayerDataSource = BetterPlayerDataSource(
    BetterPlayerDataSourceType.network,
    'http://your-server.com/videos/your-video.mp4',
    thumbnailSprite: sprite, // Add sprite metadata
  );

  final betterPlayerController = BetterPlayerController(
    BetterPlayerConfiguration(
      controlsConfiguration: BetterPlayerControlsConfiguration(
        enableThumbnailPreview: true, // Enable thumbnail preview
      ),
    ),
    betterPlayerDataSource: betterPlayerDataSource,
  );
}
```

## Part 3: Testing

### Test the Server

```bash
# Start the server
npm start

# Upload a test video
curl -X POST -F "video=@test-video.mp4" \
  -F "interval=5" \
  -F "thumbnailWidth=160" \
  -F "thumbnailHeight=90" \
  http://localhost:3000/api/upload/video
```

### Test in Flutter

```dart
void testThumbnailPreview() {
  // Test with sprite (shows all frames)
  final dataSourceWithSprite = BetterPlayerDataSource(
    BetterPlayerDataSourceType.network,
    'https://your-server.com/videos/video.mp4',
    thumbnailSprite: BetterPlayerThumbnailSprite(
      spriteUrl: 'https://your-server.com/thumbnails/video_sprite.jpg',
      vttUrl: 'https://your-server.com/vtt/video_thumbnails.vtt',
      interval: 5,
      width: 160,
      height: 90,
      columns: 10,
      rows: 12,
      totalFrames: 120,
    ),
  );

  // Without sprite (only buffered frames)
  final dataSourceWithoutSprite = BetterPlayerDataSource(
    BetterPlayerDataSourceType.network,
    'https://your-server.com/videos/video.mp4',
    // thumbnailSprite is null
  );
}
```

## Performance Considerations

1. **Sprite Size**: Balance between quality and file size

   - 160x90px thumbnails work well for mobile
   - Consider 320x180px for tablets/desktops
   - JPEG quality 80-85% is optimal

2. **Frame Interval**:

   - 5 seconds: Good for most videos (12 frames/minute)
   - 3 seconds: Better precision, larger sprite
   - 10 seconds: Smaller sprite, less precision

3. **Caching**:

   - Cache sprite images aggressively (30+ days)
   - Use CDN for better performance
   - Consider lazy loading for very long videos

4. **Processing Time**:
   - 5-minute video: ~30-60 seconds
   - 30-minute video: ~3-5 minutes
   - Consider background job queue for production

## Advanced Features

### 1. Progressive Sprite Loading

For very long videos, generate multiple sprite sheets:

```javascript
// Generate sprite in chunks
async function generateProgressiveSprites(videoPath, chunkDuration = 600) {
  const duration = await getVideoDuration(videoPath);
  const chunks = Math.ceil(duration / chunkDuration);

  const sprites = [];
  for (let i = 0; i < chunks; i++) {
    const startTime = i * chunkDuration;
    const sprite = await generateSprite(videoPath, {
      startTime,
      duration: chunkDuration,
      outputName: `sprite_${i}.jpg`,
    });
    sprites.push(sprite);
  }

  return sprites;
}
```

### 2. Adaptive Quality

Generate multiple sprite qualities:

```javascript
const qualities = [
  { width: 120, height: 68, name: "low" },
  { width: 160, height: 90, name: "medium" },
  { width: 320, height: 180, name: "high" },
];

for (const quality of qualities) {
  await generateSprite(videoPath, quality);
}
```

### 3. WebP Support

Use WebP for better compression:

```javascript
.outputOptions('-q:v', '75')
.outputFormat('webp')
.output(outputPath.replace('.jpg', '.webp'))
```

## Deployment Checklist

- [ ] FFmpeg installed on server
- [ ] Sufficient disk space for uploads and sprites
- [ ] Configure max upload size
- [ ] Set up CDN for serving sprites
- [ ] Implement upload authentication
- [ ] Add video processing queue (Bull, BullMQ)
- [ ] Monitor processing times
- [ ] Set up error notifications
- [ ] Implement cleanup for old files
- [ ] Add rate limiting on upload endpoint

## Summary

This implementation provides:

- ✅ **Unbuffered frame preview** - See any frame without buffering
- ✅ **Efficient bandwidth** - Single sprite download vs multiple seeks
- ✅ **Fast seek preview** - No network delay during scrubbing
- ✅ **Backwards compatible** - Falls back to real-time preview if no sprite
- ✅ **Production ready** - Used by YouTube, Netflix, etc.

The current Better Player Plus implementation already has the thumbnail preview UI. You just need to:

1. Set up the Node.js server
2. Add the sprite model classes to Flutter
3. Update the progress bar to support sprite-based thumbnails
4. Upload videos through your server to generate sprites

This gives you YouTube-quality thumbnail previews! 🎬
