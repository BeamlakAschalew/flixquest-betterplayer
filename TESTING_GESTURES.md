# Testing Gesture Controls

## How to Test

### 1. Rebuild the App
```bash
cd /home/beamlak/Documents/flutter/flixquest
flutter clean
flutter pub get
flutter run
```

### 2. Play a Video
- Open any movie or TV show
- Wait for the video to start playing

### 3. Test Gestures

#### Volume Control (RIGHT SIDE)
1. Place your finger on the **RIGHT side** of the screen (right 35%)
2. Swipe **UP** to increase volume
3. Swipe **DOWN** to decrease volume
4. You should see a volume indicator overlay appear

#### Brightness Control (LEFT SIDE)
1. Place your finger on the **LEFT side** of the screen (left 35%)
2. Swipe **UP** to increase brightness
3. Swipe **DOWN** to decrease brightness
4. You should see a brightness indicator overlay appear

#### Seek Control (CENTER)
1. Place your finger in the **CENTER** of the screen
2. Swipe **RIGHT** to seek forward
3. Swipe **LEFT** to seek backward
4. You should see a fast-forward/rewind indicator

## Visual Indicators

When gestures work correctly, you should see:

### Volume Indicator
```
┌─────────────┐
│   🔊 ICON   │
│  ████████░░  │  <- Progress bar
│     85%      │
└─────────────┘
```

### Brightness Indicator
```
┌─────────────┐
│   ☀️ ICON   │
│  ██████░░░░  │  <- Progress bar
│     60%      │
└─────────────┘
```

### Seek Indicator
```
┌─────────────┐
│   ⏩ +10s   │  (or ⏪ -10s)
└─────────────┘
```

## Troubleshooting

### If gestures don't work:

1. **Make sure you rebuilt the app after changes**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **Check you're swiping in the correct zones:**
   - LEFT 35% = Brightness
   - CENTER 30% = Seek
   - RIGHT 35% = Volume

3. **Swipe distance matters:**
   - You need to swipe at least 10 pixels for gesture to trigger
   - Try making longer swipes

4. **Make sure video is playing:**
   - Gestures work even when controls are hidden
   - But the video should be loaded

5. **Check Android permissions:**
   - Brightness control should work without extra permissions
   - Volume control uses the media volume

### Debug Mode

To see if gestures are being detected, you can temporarily add debug prints:

Edit `/home/beamlak/Documents/flutter/flixquest-betterplayer/lib/src/controls/better_player_gesture_controls.dart`

In the `_onVerticalDragStart` method, add:
```dart
print('DEBUG: Gesture started on ${isLeftSide ? "LEFT" : "RIGHT"} side');
```

Then check the Flutter logs:
```bash
flutter logs
```

## Common Issues

### Issue: "No visual feedback appears"
**Solution:** The overlay might be appearing but very briefly. Try:
1. Increasing `feedbackDuration` in configuration
2. Making sure you're not accidentally tapping (which hides controls)

### Issue: "Brightness doesn't change"
**Solution:** 
- On Android: Brightness changes should work automatically
- Test by swiping up/down slowly on the LEFT side
- Check if device brightness control is locked

### Issue: "Volume doesn't change"
**Solution:**
- Make sure device is not in silent mode
- Check media volume is not at 0
- Try pressing hardware volume buttons first to ensure volume works

### Issue: "Gestures interfere with video controls"
**Solution:**
- Gestures should work alongside existing controls
- If controls are blocking gestures, try hiding controls first (tap once)
- Gestures work even when controls are hidden

## Expected Behavior

✅ **Correct:**
- Swipe on LEFT side → Brightness changes with visual feedback
- Swipe on RIGHT side → Volume changes with visual feedback  
- Swipe in CENTER → Video seeks with visual feedback
- Feedback overlay appears for ~500ms
- Gestures work in fullscreen and normal mode

❌ **Incorrect:**
- No visual feedback when swiping
- Nothing happens when swiping
- Only the video player controls respond to touches
