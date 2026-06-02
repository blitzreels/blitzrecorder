# User workflow

The app should make this workflow clear.

## Record a Mac video

1. Choose the screen source.
2. Choose an optional camera source.
3. Choose microphone and system audio when needed.
4. Pick a 9:16 or 16:9 canvas.
5. Frame the screen and camera.
6. Press Record.
7. Pause and resume if needed.
8. Stop and wait for the final export.

## Use an iPhone as a camera

1. Open BlitzRecorder Camera on iPhone.
2. Keep the iPhone and Mac on the same local network.
3. Pair using the code shown on the iPhone.
4. Select the iPhone in the Mac camera picker.
5. Adjust supported camera controls from the Mac.
6. Record from the Mac.
7. Keep the iPhone app open until the camera file transfers back.

## After recording

The post-recording state should always make the next action clear:

- Open the finished video.
- Reveal the file in Finder.
- Rename or move the export.
- Reveal source files when saved.
- Retry export from recovery files when possible.
- Start a new take.

## Recovery expectations

A failed export should not feel like a lost recording. BlitzRecorder should keep source files when possible and show the recovery folder with a retry path when enough media exists.
