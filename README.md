# Winnow

A native macOS app for viewing Fujifilm photos straight off an SD card, culling them (pick / reject), and importing only the picks. After a verified import it offers to delete the imported photos from the card. It never formats the card.

Requires macOS 26 (Tahoe) on Apple silicon. Apple frameworks only, no dependencies.

## Build and run

Open `Winnow.xcodeproj` in Xcode 27 and run the **Winnow** scheme, or:

```sh
xcodebuild -project Winnow.xcodeproj -scheme Winnow -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Winnow.app
xcodebuild -project Winnow.xcodeproj -scheme Winnow -derivedDataPath build/DerivedData test
```

Insert a card and Winnow comes forward and opens it. A card is any removable volume with a `DCIM/` folder. You can also use **File › Open Folder…** (⌘O) to browse any folder.

## Look

Winnow follows the system appearance (light or dark) and uses Apple's own containers, so Liquid Glass comes from the system:
- `NavigationSplitView` for the sidebar
- the unified window toolbar
- `.inspector` for photo info in the large view
- a standard sheet with a grouped `Form` for import

Custom glass (`glassEffect`) is only used for Winnow's own floating controls: the key-hint pill, the filmstrip and the previous / next buttons. Badges on the photos themselves are solid, because Apple reserves glass for controls that float above content.

## App icon

`Winnow/AppIcon.icon` is an Icon Composer icon: a strip of film on a lightbox, with the picked frame lit amber. It has a warm cream fill and two layers, `film.png` and `pick.png`. macOS adds the glass, the shadows and the dark and tinted variants. You can open it in Icon Composer (inside Xcode) to adjust it. To redraw the layers:

```sh
swiftc -O -o /tmp/make-layers Design/AppIcon/make-layers.swift && /tmp/make-layers Winnow/AppIcon.icon/Assets
```

## Keys

| Key | Action |
|---|---|
| P / X / U | pick / reject / clear |
| Space or Return | open large view; Space again returns to the grid |
| ← → | previous / next photo |
| ↑ ↓ | move by row in the grid |
| Z | Fit / 100% in the large view |
| Esc | back to grid / dismiss sheet |
| ⌘= / ⌘- | bigger / smaller thumbnails |
| ⌘I | import picks |
| ⌘E | eject card |

Mouse: click a thumbnail to select it, click the selected one again to cycle its flag (none → pick → reject), double-click to view it large.

## How it works

- **Scanning** walks `DCIM/*/`, pairs `DSCF4503.RAF` with `DSCF4503.JPG` (case-insensitive), and skips macOS `._` files.
- **Previews** come from whichever camera-rendered JPEG is fewer bytes to read: the JPG sibling or the preview embedded in the RAF. On an X-E5 the embedded preview is about a third the size of the JPG, so it loads about 2.5× faster. RAW is only decoded (with `CIRAWFilter`) for 100% zoom. At most 4 reads run at once, and reads for cells that scroll away are cancelled.
- **Flags and import records** live in `~/Library/Application Support/Winnow/cards/<volume UUID>.json`, so they survive eject and reinsert.
- **Import** copies each file to a hidden `.<name>.winnow-partial`, hashes what it read from the card and what landed on disk (SHA-256, read back past the page cache), retries once on a mismatch, then renames the file into place and keeps the original dates. If a file with the same name and contents already exists, it is counted as already imported. A different file with the same name gets a `-1`, `-2` suffix.
- **Delete from card** only removes source files whose copies were verified in that import (plus rejects, if you tick the box). It skips any file whose size changed since it was copied. It uses `removeItem`, not the Trash, so the space is freed on the card.

## Notes

- **App Sandbox is off** (personal app): Winnow needs to read any removable volume and write to any folder you choose. Hardened runtime is on for Release builds. It is off for Debug so the hosted unit tests can load into the app.
- macOS asks once for permission to read removable volumes.
- "Open folder in Lightroom" appears only when Lightroom Classic is installed.
- Debug builds accept `-open <folder>` to open a folder at launch. `-snapshots <dir>` walks the main screens and saves a PNG of each. Add `-appearance light` or `-appearance dark` to pick a mode. The capture can't render system glass, so custom glass is drawn flat and the sidebar and toolbar look wrong in snapshots.

## Layout

```
Winnow/
  WinnowApp.swift
  Models/     AppModel, CardSession, ImportFlow, Photo, Flag, ImportRecord
  Services/   VolumeWatcher, CardScanner, PreviewLoader, ExifReader, Importer, CardStore
  Views/      RootView, BrowseView, SidebarView, GridView, LoupeView, ImportSheet, ImportProgressView
  Support/    KeyCommands, Theme, DebugSnapshots
WinnowTests/    CardScannerTests, ImporterTests, CardStoreTests
```
