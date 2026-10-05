# Embezel

A small macOS app that wraps an iPhone screenshot or screen recording in a
photorealistic device frame. Drag in a screenshot, pick a device color, drag
the framed image back out — or export it as a PNG.

## Features

- Drag-and-drop a `.png`/`.jpg` screenshot onto the window, or open it from the
  toolbar.
- Automatic device detection based on the screenshot's pixel dimensions. The
  picker lists every model and color that matches, newest model first.
- Portrait and landscape screenshots. Landscape frames can be rotated 180° to
  put the Dynamic Island on either side; the app makes an experimental guess
  at which side it was.
- iPhone Duo in all its poses: outer display closed (portrait and landscape)
  or open, and inner display open (portrait and landscape).
- Screen recordings (`.mov`/`.mp4`) from the iPhone, the Simulator or
  QuickTime are framed too, with a looping preview. Export as HEVC with a
  transparent background (`.mov`; QuickTime, Safari, Keynote, Final Cut) or
  on a solid color (`.mp4`, plays anywhere). Audio is kept.
- The window resizes to fit the frame's shape.
- Drag the framed result straight into another app, export it to a PNG, or let
  the app copy it to the clipboard automatically.
- Sparkle-based auto-update.

## Supported devices

iPhone 16, 16 Plus, 16 Pro, 16 Pro Max, 17, Air, 17 Pro, 17 Pro Max, 18 Pro,
18 Pro Max and Duo, each with the color variants Apple shipped. Only
screenshots whose pixel dimensions exactly match one of these devices are
accepted. Screen recordings may also be downscaled (the iPhone's own screen
recorder doesn't always record at full resolution): if no device matches
exactly, every device with the same screen aspect ratio is offered and the
recording is scaled to fit.

Version 2.0.0 dropped the iPhone 14 and 15 frames. Screenshots from the
iPhone 14 Pro, 14 Pro Max and the iPhone 15 family have the same size as
iPhone 16 models and are framed with those.

## Installing

Download the latest `Embezel-x.y.z.dmg` from the
[Releases](https://github.com/apparata/Embezel/releases) page and drop
`Embezel.app` into `/Applications`. The app updates itself via Sparkle using
`appcast.xml` in this repository.

## License

0BSD. For details see [LICENSE](LICENSE). Third-party components are listed in
[ATTRIBUTIONS.md](ATTRIBUTIONS.md).
