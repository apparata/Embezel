//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit

enum AppError: Error {
    case unsupportedScreenshotSize
    case droppedDevice(String)
    case unsupportedFile

    var message: String {
        switch self {
        case .unsupportedScreenshotSize:
            "Unsupported screenshot size"
        case .droppedDevice(let device):
            "\(device) screenshots are no longer supported"
        case .unsupportedFile:
            "Unsupported file"
        }
    }
}

/// A model and color, as chosen in the picker.
struct ModelColor: Hashable {
    let model: String
    let color: String
}

@MainActor @Observable class ContentModel {

    var screenshot: NSImage?

    /// Bezels that fit the current screenshot, in catalog order.
    private(set) var candidates: [Bezel] = []

    private(set) var selection: Selection?

    var compositedImage: NSImage?

    @ObservationIgnored private var screenshotImage: CGImage?
    @ObservationIgnored private var bezelImages: [String: CGImage] = [:]
    @ObservationIgnored private var screenMasks: [String: CGImage] = [:]

    /// Sizes that only 1.x devices had, so a clearer message can be shown.
    private static let droppedDevices: [(portraitSize: CGSize, name: String)] = [
        (CGSize(width: 1170, height: 2532), "iPhone 14"),
        (CGSize(width: 1284, height: 2778), "iPhone 14 Plus")
    ]

    func clear() {
        screenshot = nil
        screenshotImage = nil
        candidates = []
        selection = nil
        compositedImage = nil
    }

    // MARK: - Picker Support

    /// Models that fit the current screenshot, newest first.
    var models: [String] {
        candidates.map(\.model).uniqued()
    }

    func colors(for model: String) -> [String] {
        candidates.filter { $0.model == model }.map(\.color).uniqued()
    }

    /// Poses of the selected model and color that fit the screenshot.
    var poses: [Pose] {
        guard let bezel = selection?.bezel else {
            return []
        }
        return candidates
            .filter { $0.model == bezel.model && $0.color == bezel.color }
            .map(\.pose)
    }

    var selectedModelColor: ModelColor? {
        selection.map { ModelColor(model: $0.bezel.model, color: $0.bezel.color) }
    }

    func select(_ modelColor: ModelColor) {
        let matching = candidates.filter { $0.model == modelColor.model && $0.color == modelColor.color }
        guard let bezel = matching.first(where: { $0.pose == selection?.bezel.pose }) ?? matching.first else {
            return
        }
        select(Selection(bezel: bezel, isRotated180: selection?.isRotated180 ?? false))
    }

    func select(_ pose: Pose) {
        guard let current = selection?.bezel, let bezel = candidates.first(where: {
            $0.model == current.model && $0.color == current.color && $0.pose == pose
        }) else {
            return
        }
        select(Selection(bezel: bezel, isRotated180: selection?.isRotated180 ?? false))
    }

    func toggleRotation() {
        guard let selection, selection.bezel.pose.isLandscape else {
            return
        }
        select(Selection(bezel: selection.bezel, isRotated180: !selection.isRotated180))
    }

    private func select(_ selection: Selection) {
        self.selection = selection
        makeComposite()
    }

    // MARK: - Loading

    func loadScreenshot(_ image: NSImage) throws {
        try setScreenshot(normalizeImageSizeTo1x(image))
    }

    func loadScreenshot(from url: URL, isSecurityScoped: Bool = false) throws {
        if isSecurityScoped {
            guard url.startAccessingSecurityScopedResource() else {
                print("Couldn't access security-scoped resource.")
                throw AppError.unsupportedFile
            }
        }
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let image = NSImage(contentsOf: url) else {
            print("Could not load image at \(url.absoluteString)")
            throw AppError.unsupportedFile
        }

        try setScreenshot(normalizeImageSizeTo1x(image))
    }

    private func normalizeImageSizeTo1x(_ image: NSImage) -> NSImage {

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let newImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return newImage
    }

    /// Picks the default bezel for a new screenshot: the first match in
    /// catalog order is the newest model, its alphabetically first color,
    /// and its first pose (Closed before Open for the Duo outer display).
    private func setScreenshot(_ image: NSImage) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AppError.unsupportedFile
        }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let matches = BezelCatalog.all.filter { $0.screenshotSize == size }

        guard let bezel = matches.first else {
            let portraitSize = size.width > size.height ? CGSize(width: size.height, height: size.width) : size
            if let device = Self.droppedDevices.first(where: { $0.portraitSize == portraitSize }) {
                throw AppError.droppedDevice(device.name)
            }
            throw AppError.unsupportedScreenshotSize
        }

        screenshot = image
        screenshotImage = cgImage
        candidates = matches
        let isRotated180 = bezel.pose.isLandscape && RotationDetector.detect(cgImage) == .rotated180
        select(Selection(bezel: bezel, isRotated180: isRotated180))
    }

    // MARK: - Compositing

    private func makeComposite() {
        guard let screenshotImage, let selection,
              let bezelImage = bezelImage(for: selection.bezel),
              let screenMask = screenMask(for: selection.bezel, bezelImage: bezelImage),
              let image = BezelRenderer.render(
                screenshot: screenshotImage,
                bezelImage: bezelImage,
                screenMask: screenMask,
                selection: selection
              ) else {
            compositedImage = nil
            return
        }

        let composite = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        compositedImage = composite
        copyImageToPasteboard(composite)
    }

    /// Loads the bezel at its full pixel size. The PNGs are tagged 216 dpi,
    /// so the image's point size must not be used for geometry.
    private func bezelImage(for bezel: Bezel) -> CGImage? {
        if let image = bezelImages[bezel.imageName] {
            return image
        }
        var rect = CGRect(origin: .zero, size: bezel.canvasSize)
        guard let image = NSImage(named: bezel.imageName)?.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              image.width == Int(bezel.canvasSize.width),
              image.height == Int(bezel.canvasSize.height) else {
            print("Could not load bezel image \(bezel.imageName)")
            return nil
        }
        bezelImages[bezel.imageName] = image
        return image
    }

    private func screenMask(for bezel: Bezel, bezelImage: CGImage) -> CGImage? {
        if let mask = screenMasks[bezel.imageName] {
            return mask
        }
        let mask = BezelRenderer.makeScreenMask(bezelImage: bezelImage, bezel: bezel)
        screenMasks[bezel.imageName] = mask
        return mask
    }

    func copyImageToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

// MARK: - Helpers

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
