# Embezel

A small macOS app that wraps an iPhone screenshot in a photorealistic device
frame. Drag in a screenshot, pick a device color, drag the framed image back
out — or export it as a PNG.

## Features

- Drag-and-drop a `.png`/`.jpg` screenshot onto the window, or open it from the
  toolbar.
- Automatic device detection based on the screenshot's pixel dimensions. The
  picker lists every color variant that matches the detected device.
- Drag the framed result straight into another app, export it to a PNG, or let
  the app copy it to the clipboard automatically.
- Menu bar companion window, in-app Help window, and Sparkle-based auto-update.

## Supported devices

iPhone 14, 14 Plus, 14 Pro, 14 Pro Max, 15, 15 Plus, 15 Pro, 15 Pro Max, 16,
16 Plus, 16 Pro, 16 Pro Max — each with the color variants Apple shipped.
Only screenshots whose pixel dimensions exactly match one of these devices are
accepted.

## Installing

Download the latest `Embezel-x.y.z.dmg` from the
[Releases](https://github.com/apparata/Embezel/releases) page and drop
`Embezel.app` into `/Applications`. The app updates itself via Sparkle using
`appcast.xml` in this repository.

## License

0BSD. For details see [LICENSE](LICENSE). Third-party components are listed in
[ATTRIBUTIONS.md](ATTRIBUTIONS.md).
