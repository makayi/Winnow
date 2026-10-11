# Product demo

A 34-second portrait (1080×1920) demo, recorded from the real app.

1. **Record.** A debug build plays a scripted walkthrough (`Winnow/Support/DemoAutopilot.swift`) on a scratch copy of a card and records the window with ScreenCaptureKit. The walkthrough imports and deletes for real, so only point it at a copy.

   ```sh
   mkdir -p /tmp/DemoCard/DCIM/100_FUJI && cp -c <some RAF/JPG files> /tmp/DemoCard/DCIM/100_FUJI/
   build/DerivedData/Build/Products/Debug/Winnow.app/Contents/MacOS/Winnow \
     -open /tmp/DemoCard -folderIsCard YES -demo /tmp/demo -demoImportTo /tmp/DemoImport -appearance light &
   osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "Winnow") to true'
   ```

   Launch it from a terminal that has Screen Recording permission, and leave the window alone while it records (about 30 s). It writes `recording.mov` and `timeline.json` (scene and key-press times).

2. **Render the stills** (background, cards, captions, key badges):

   ```sh
   swiftc -O -o /tmp/make-assets Design/Demo/make-assets.swift
   /tmp/make-assets /tmp/edit "$PWD/build/DerivedData/Build/Products/Debug/Winnow.app"
   ```

3. **Music:** the current cut uses "Product – Product Launch" by lNPLUSMUSIC from Pixabay ([track](https://pixabay.com/music/upbeat-product-product-launch-611921/), Pixabay Content License: free for commercial use, no credit required). `mix-music.py` lays it under the video with very soft key clicks:

   ```sh
   python3 Design/Demo/mix-music.py /tmp/demo/timeline.json track.mp3 /tmp/edit/music.wav --t0 4.898 --offset 0.24
   ```

   The track starts 0.24 s in, so its opening hit lands on the first card and its second hit (5.14 s) lands exactly when the app appears. (`make-audio.py` can still synthesise a placeholder track in code.)

4. **Compose with motion:** `render-demo.swift` draws every frame itself. A virtual camera, set up in `camera.json`, zooms and pans over the recording with eased moves and a small punch-in on each pick. The window springs in on the music's hit, captions slide in, key badges pop, and the background drifts gently. Then add the audio:

   ```sh
   swiftc -O -o /tmp/render-demo Design/Demo/render-demo.swift
   /tmp/render-demo /tmp/demo /tmp/edit Design/Demo/camera.json /tmp/edit/motion.mov 4.898 0,2.364
   ffmpeg -i /tmp/edit/motion.mov -i /tmp/edit/music.wav -filter_complex "[1:a]loudnorm=I=-16:TP=-1.5:LRA=11[a]" \
     -map 0:v -map "[a]" -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k -shortest winnow-demo.mp4
   ```

   `build-video.py` still makes a simpler cut with no camera moves.
