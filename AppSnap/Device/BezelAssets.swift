//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit

/// Loads bezel images and their screen masks, and caches both by image name.
@MainActor final class BezelAssets {

    static let shared = BezelAssets()

    private var images: [String: CGImage] = [:]
    private var masks: [String: CGImage] = [:]
    private var maskTasks: [String: Task<CGImage?, Never>] = [:]

    /// Loads the bezel at its full pixel size. The PNGs are tagged 216 dpi,
    /// so the image's point size must not be used for geometry.
    func image(for bezel: Bezel) -> CGImage? {
        if let image = images[bezel.imageName] {
            return image
        }
        var rect = CGRect(origin: .zero, size: bezel.canvasSize)
        guard let image = NSImage(named: bezel.imageName)?.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              image.width == Int(bezel.canvasSize.width),
              image.height == Int(bezel.canvasSize.height) else {
            print("Could not load bezel image \(bezel.imageName)")
            return nil
        }
        images[bezel.imageName] = image
        return image
    }

    /// The bezel image and screen mask, computing the mask on the main
    /// thread if it isn't cached yet.
    func assets(for bezel: Bezel) -> (image: CGImage, mask: CGImage)? {
        guard let image = image(for: bezel) else {
            return nil
        }
        if let mask = masks[bezel.imageName] {
            return (image, mask)
        }
        guard let mask = BezelRenderer.makeScreenMask(bezelImage: image, bezel: bezel) else {
            return nil
        }
        masks[bezel.imageName] = mask
        return (image, mask)
    }

    /// The bezel image and screen mask, computing the mask in the
    /// background. The flood fill takes a while for large bezels, which
    /// matters when a batch needs many of them.
    func loadAssets(for bezel: Bezel) async -> (image: CGImage, mask: CGImage)? {
        guard let image = image(for: bezel) else {
            return nil
        }
        if let mask = masks[bezel.imageName] {
            return (image, mask)
        }
        let task: Task<CGImage?, Never>
        if let existing = maskTasks[bezel.imageName] {
            task = existing
        } else {
            task = Task.detached(priority: .userInitiated) {
                BezelRenderer.makeScreenMask(bezelImage: image, bezel: bezel)
            }
            maskTasks[bezel.imageName] = task
        }
        guard let mask = await task.value else {
            return nil
        }
        masks[bezel.imageName] = mask
        maskTasks[bezel.imageName] = nil
        return (image, mask)
    }
}
