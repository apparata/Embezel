# CLAUDE.md

Embezel is a SwiftUI macOS app (macOS 14+, Swift 5.10, arm64 releases) that
composites an iPhone screenshot into a photorealistic device bezel image. The
user drops a screenshot, the app detects which devices match its pixel size,
the user picks a color variant, and the framed PNG can be dragged out,
exported, or is copied to the clipboard automatically.

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
- The Xcode project is the source of truth and is edited directly.
  `XcodeProject.yml` (XcodeGen) is stale and being removed; it doesn't even
  list Sparkle.
- `.swiftlint.yml` is an opt-in rule list (`only_rules`) with custom naming
  rules (`setUp`/`shutDown`/`logIn`/`logOut`, no `vc`). No build phase runs
  SwiftLint; run it manually with `mint run swiftlint` (see `Mintfile`) if
  needed. `force_unwrapping` and `force_try` are enabled, so use
  `// swiftlint:disable:next` when a force unwrap is intentional.
- Dependencies are SPM packages: Sparkle plus several of Apparata's own
  packages (`SwiftUIToolbox` supplies `AboutWindow`/`AboutCommand`,
  `AttributionsUI`, `CGMath` for `CGSize`/`CGPoint` operators,
  `CollectionKit`, `Constructs`, and others). Versions are pinned in
  `AppSnap.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Architecture

All the real logic lives in three files:

- `AppSnap/Device/Device.swift`: the static device catalog. Each `Device` has
  a name, a `[variantName: NSImage]` bezel image map, a screen `mask` image,
  a `maskOffset` (top-left position of the screen inside the bezel image), and
  the native `screenSize` in pixels. `Device.all` sets the order of the
  picker sections.
- `AppSnap/ContentModel.swift`: an `@MainActor @Observable` model.
  - `loadScreenshot` turns the image into a 1x `NSImage` whose point size
    equals its pixel size (`normalizeImageSizeTo1x`), then rejects it with
    `AppError.unsupportedScreenshotSize` unless it exactly matches some
    device's `screenSize`. Retina-scaled images would fail the match without
    this step (commit 968d7a3 fixed that).
  - `makeComposite` builds `candidates` (every device and variant with a
    matching screen size, grouped by device), keeps the current selection if
    it's still valid or falls back to the first candidate, then renders the
    bezel image with the screenshot overlaid at `maskOffset` and masked by
    `device.mask` using SwiftUI `ImageRenderer`. It then copies the result to
    the pasteboard.
  - `makeVideo` does the same for `.mp4`/`.mov` screen recordings via
    `AppSnap/Video Creation/FramedVideo.swift` (AVFoundation and a
    Core Animation layer composition at 0.5x scale, exported as HEVC). The
    output goes to a temp file and the folder opens in Finder. Video is only
    reachable through the file importer, and the README doesn't mention it.
- `AppSnap/ContentView.swift`: the single main view. Inputs are drag and drop
  (`NSImage` and `URL`), `onOpenURL`, and `.fileImporter`. File-importer
  URLs are security-scoped (`isSecurityScoped: true`). The toolbar has open,
  clear (plays the Metal dissolve shader `removeEffect` in
  `AppSnap/Effects/RemoveEffect.metal`), and export-to-PNG. Errors show up as
  a `Toast`.

Scenes are registered in `AppSnap/MacApp.swift`: the main window, menu bar
extra, settings, about, attributions, and help. Sparkle's
`SPUStandardUpdaterController` lives there too and feeds
`CheckForUpdatesCommand`.

### Template leftovers

The project started from an app template, and several files are still
placeholders that do nothing useful: `MenuBarPopup` ("Hello, World!"),
`MyCommands` (a "My Commands" menu with print-only Build/Do Stuff items bound
to ⌘B/⌘D), `GeneralSettingsTab`, `HelpWindow` ("No help available."),
`RemoveEffectView` (a shader demo), and the unused `WindowReflection` /
`NSWindow+AlwaysOnTop` helpers. Don't assume these are intentional features.

## Adding a new device

1. In `AppSnap/Assets.xcassets/Device/`, add a folder named after the device
   (e.g. `iPhone 17 Pro`) with **Provides Namespace** enabled. Inside it, add
   one imageset per color variant plus a `Mask` imageset. All images are
   single-scale (`universal`, 1x).
2. The mask PNG must be exactly the device's screen size in pixels. It has an
   alpha channel, and opaque pixels mark the visible screen area (SwiftUI
   `.mask` uses alpha), including rounded corners and the Dynamic Island
   cutout.
3. Xcode generates asset symbols (`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`),
   so images are referenced as `.Device.IPhone17Pro.blackTitanium`,
   `.Device.IPhone17Pro.mask`, and so on.
4. Add a `static let` in `Device.swift` and include it in `Device.all`. Find
   `maskOffset` by aligning the mask inside the bezel image. These values are
   hand-tuned per device and are not always symmetric.
5. Devices that share a `screenSize` all show up as candidates for the same
   screenshot. That's intended; the user picks the right one.
6. Update the supported-devices list in `README.md`.

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

- New Swift files start with the `// Copyright © 2025 Apparata AB. All rights
  reserved.` header block, use 4-space indentation, and use `// MARK: -`
  sections.
- Use Swift Observation (`@Observable`, `@State`), not `ObservableObject`.
- License is 0BSD. Third-party notices go in `ATTRIBUTIONS.md` and in the
  `AttributionsWindow` list in `MacApp.swift`.
