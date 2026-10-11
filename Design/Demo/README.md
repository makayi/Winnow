# Product demo

A 33-second portrait (1080×1920) demo, recorded from the real app.

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

3. **Soundtrack:** `python3 Design/Demo/make-audio.py /tmp/demo/timeline.json /tmp/edit/soundtrack.wav` composes an upbeat 120 bpm cue in D major (four-on-the-floor drums, bass, chord stabs and a lead hook), plus soft key clicks and a chime when the import lands. It's all generated in code, so there's nothing to license.

4. **Compose:** `python3 Design/Demo/build-video.py /tmp/demo /tmp/edit winnow-demo.mp4 /tmp/edit/soundtrack.wav` (the audio is normalised to −16 LUFS).

Captions are in `make-assets.swift`; the timing comes from `timeline.json`.
