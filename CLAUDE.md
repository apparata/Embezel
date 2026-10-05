# CLAUDE.md

Embezel is a SwiftUI macOS app (macOS 14+, Swift 5.10, arm64 releases) that
composites an iPhone screenshot into a photorealistic device bezel image. The
user drops a screenshot, the app detects which devices match its pixel size,
the user picks a color variant, and the framed PNG can be dragged out,
exported, or is copied to the clipboard automatically. Screen recordings are
framed too and exported as HEVC video. Supported devices are
the iPhone 16, 17 (including Air), 18 Pro/Pro Max and Duo families, in portrait
and landscape, and in every Duo pose.

## Naming

The product is **Embezel**, but nearly everything internal still uses the
original name **AppSnap**: the Xcode project (`AppSnap.xcodeproj`), target,
source folder (`AppSnap/`), schemes (`AppSnap (Debug)` / `AppSnap (Release)`),
and bundle ID (`se.apparata.AppSnap`). Only `PRODUCT_NAME` is `Embezel`, so
the built app is `Embezel.app`. Don't rename the bundle ID: Sparkle updates
and existing installs depend on it.

## Build

```bash
xcodebuild -project AppSnap.xcodeproj -scheme "AppSnap (Debug)" -destination 'platform=macOS' build
```

- There are no tests and no test target.
- The Xcode project is the source of truth and is edited directly. Most
  folders under `AppSnap/` are synchronized folders
  (`PBXFileSystemSynchronizedRootGroup`): new files in them are picked up
  automatically, but adding or removing a whole folder needs a
  `project.pbxproj` edit.
- `.swiftlint.yml` is an opt-in rule list (`only_rules`) with custom naming
  rules (`setUp`/`shutDown`/`logIn`/`logOut`, no `vc`). No build phase runs
  SwiftLint; run it manually with `mint run swiftlint` (see `Mintfile`) if
  needed. `force_unwrapping` and `force_try` are enabled, so use
  `// swiftlint:disable:next` when a force unwrap is intentional.
- Dependencies are SPM packages: Sparkle, `SwiftUIToolbox` (`AboutWindow`,
  `AboutCommand`), `AttributionsUI` and `Constructs` (`.applying`). Versions
  are pinned in
  `AppSnap.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Architecture

### Bezels and geometry

- `AppSnap/Device/Bezel.swift`: `Bezel` (model, color, `Pose`, image name,
  canvas size, screen rectangle) and `Selection` (a bezel plus an optional
  180° rotation, which only applies to landscape poses). All geometry is in
  pixels with a **top-left origin**, as in the source PSDs. A screenshot fits
  a bezel when its pixel size equals `screenRect.size`; screenshots are always
  placed 1:1, never scaled.
- `AppSnap/Device/BezelCatalog.swift`: **generated, don't edit**. It is the
  committed record of every bezel's geometry, in model order (newest first),
  then color (alphabetical), then pose.
- `AppSnap/Assets.xcassets/Bezels/`: **generated**. The source PNGs, copied
  unchanged, one imageset per PNG named after the file. Loaded by name; the
  PNGs are tagged 216 dpi, so always use pixel sizes, never `NSImage.size`.
- `AppSnap/Device/BezelRenderer.swift`: pure Core Graphics. The screenshot is
  drawn **under** the bezel. The bezel PNG has a transparent screen hole with
  the Dynamic Island drawn opaque, so the bezel does most of the clipping.
  The screen rectangle's corners stick out past the phone's rounded outer
  corners, though, so the screenshot is also clipped by a screen mask that
  `makeScreenMask` computes from the bezel's alpha. It flood-fills the
  non-opaque pixels reachable from the canvas border ("outside the phone").
  Output keeps the screenshot's color space (usually Display P3).
- `AppSnap/Device/VideoBezelComposer.swift`: the video counterpart of
  `BezelRenderer`, an `AVVideoComposition` with a Core Image handler that does
  the same mask + bezel composite per frame. Unlike screenshots, recordings
  are **scaled** to fill the screen rectangle (aspect-fill), because on-device
  recordings are often downscaled. Frames whose size is the display size
  swapped are turned upright from the track's preferred transform.
  `renderSize` is rounded up to even dimensions for the encoder.
  `VideoBackground` is transparent or a solid color.
- `AppSnap/Device/VideoExporter.swift`: `AVAssetExportSession` export.
  Transparent goes to HEVC with alpha in `.mov`, a solid color to HEVC in
  `.mp4`. Audio is passed through. Progress is polled (macOS 14 has no
  async progress API), and cancelling the task cancels the export.
- `AppSnap/Device/RotationDetector.swift`: **experimental** guess at which side
  the Dynamic Island was on in a landscape screenshot. Screenshots contain no
  island pixels and landscape safe areas are symmetric, so it only answers when
  one edge strip is a flat color and the other has content. Otherwise it
  returns `.unknown`, which falls back to the bezel as shipped (island on the
  left). It is untuned; the rotate button is always available.

### App

- `AppSnap/ContentModel.swift`: an `@MainActor @Observable` model.
  - `loadScreenshot` normalizes the image to 1x (point size = pixel size; see
    commit 968d7a3), then finds `candidates`: all bezels with a matching
    screenshot size. Errors are `AppError` with a user-facing `message`. iPhone
    14 and 14 Plus sizes get a "no longer supported" message.
  - The default selection is the first candidate in catalog order: newest
    model, first color, first pose (Duo outer portrait defaults to Closed
    rather than Open). Rotation comes from `RotationDetector`. Nothing is
    remembered between screenshots.
  - The source is an `image` or a `video` (`AVURLAsset`). `load(from:)`
    routes movie files to `loadVideo`. Recordings match bezels exactly first;
    failing that, every bezel whose screen aspect ratio is within 1%.
    Rotation is detected on a frame near the start.
  - For a recording, `makeComposite` builds the `videoComposition`
    asynchronously (a newer selection cancels an older build) and sets it on
    the muted, looping `player`. Nothing is copied to the pasteboard.
    `freezeVideoFrame` swaps in a still frame before clearing, because the
    dissolve shader can't apply to the AppKit player view.
  - Every composite, including each picker, pose or rotation change, is
    copied to the pasteboard. Bezel images and screen masks are cached by
    image name.
- `AppSnap/ContentView.swift`: the single main view. Inputs are drag and drop
  (one `onDrop` handler for file URLs, promised movie files such as the
  Simulator's recording thumbnail, and images; stacked `dropDestination`s
  don't combine), `onOpenURL` (files opened in Finder go to the existing
  window via `handlesExternalEvents`), and `.fileImporter` (PNG, JPEG and
  movies, security-scoped URLs). Recordings play in `PlayerView`
  (`AppSnap/Utilities/PlayerView.swift`), a bare `AVPlayerLayer` with a clear
  background that passes mouse events through; click toggles playback.
  Recordings get a background control (Transparent / Color, with a help
  popover) and can't be dragged out: a drag shows an alert that offers to
  export instead. Below the preview: a model + color picker, a pose segmented
  control (only when several poses fit), and a rotate button (landscape
  only). The toolbar has open, clear (plays the Metal dissolve shader
  `removeEffect` in `AppSnap/Effects/RemoveEffect.metal`), and export (PNG,
  or a movie for recordings). When the composite's aspect changes, the window
  resizes to fit it, keeping its content area and center
  (`resizeWindowIfNeeded`, using the window from `WindowReflection`). The
  minimum width is 400 pt, because narrower windows push toolbar buttons into
  an overflow menu.

Scenes are registered in `AppSnap/MacApp.swift`: the main window, about and
attributions. Sparkle's `SPUStandardUpdaterController` lives there too and
feeds `CheckForUpdatesCommand`. `RemoveEffectView` (a shader demo) and
`NSWindow+AlwaysOnTop` are unused leftovers from the app template.

## Adding a new device

Bezels come from a source folder outside the repo (the PSDs are about 2 GB)
laid out as `<Family>/Photoshop/**/<Model> - <Color> - <Pose>.psd` with
matching `<Family>/PNG/**/<same name>.png`.

1. Put the new PSDs and PNGs in the source folder.
2. Add the model to `modelOrder` in `scripts/import-bezels.swift`, in
   newest-first position. The order drives the picker and the default
   selection when several models share a screenshot size. New pose names also
   need adding to `poses` there and to `Pose` in `Bezel.swift`.
3. Run `swift scripts/import-bezels.swift <path-to-Bezels>`. It reads each
   PSD's `Screen` layer bounds (pixel data is never extracted from PSDs),
   checks everything (missing pairs, unknown models or poses, PNG/PSD size
   mismatch, an opaque screen center, duplicates) and **writes nothing if
   anything fails**. On success it regenerates `AppSnap/Assets.xcassets/Bezels/`
   and `AppSnap/Device/BezelCatalog.swift` from scratch.
4. Update the supported-devices list in `README.md`.

Devices that share a screenshot size all show up as candidates for it. That's
intended; the user picks the right one.

## Release

`scripts/build-and-notarize.sh` runs the whole release and is interactive. It
archives the `AppSnap (Release)` scheme for arm64, exports with Developer ID
(team `DR5YAK7GKS`), builds a DMG, notarizes it with the `notary` keychain
profile, signs it for Sparkle, tags and creates a GitHub release in
`apparata/Embezel`, then regenerates `appcast.xml`. If the version needs a
bump, it updates `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
`project.pbxproj` plus `CFBundleShortVersionString` and `CFBundleVersion` in
`AppSnap/Info.plist`, and **commits and pushes** both the bump and the
appcast. Keep all four version fields in sync if you change the version by
hand. Sparkle reads the feed from `main` on GitHub (`SUFeedURL` in
`Info.plist`), so pushing `appcast.xml` publishes an update to users. Only run
this script when the user asks for a release.

## Conventions

- New Swift files start with the `// Copyright © <year> Apparata AB. All
  rights reserved.` header block, use 4-space indentation, and use `// MARK: -`
  sections.
- Use Swift Observation (`@Observable`, `@State`), not `ObservableObject`.
- License is 0BSD. Third-party notices go in `ATTRIBUTIONS.md` and in the
  `AttributionsWindow` list in `MacApp.swift`.
