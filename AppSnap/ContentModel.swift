//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit
import CollectionKit

enum AppError: Error {
    case unsupportedScreenshotSize
}

struct DeviceAndVariant: Identifiable, Equatable, Hashable {

    let device: Device
    let variant: String

    var description: String {
        device.name + " - " + variant
    }

    var id: String {
        description
    }

    static var all: [[DeviceAndVariant]] {
        Device.all.map { device in
            device.variants.map { variant in
                DeviceAndVariant(device: device, variant: variant)
            }
        }
    }

    static func == (lhs: DeviceAndVariant, rhs: DeviceAndVariant) -> Bool {
        lhs.device.name == rhs.device.name && lhs.variant == rhs.variant
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(description)
    }
}

@MainActor @Observable class ContentModel {

    var screenshot: NSImage?

    var candidates: [[DeviceAndVariant]] = []
    var selectedDeviceAndVariant = DeviceAndVariant(
        device: .iPhone16Pro,
        variant: Device.iPhone16Pro.variants[0]
    )

    var compositedImage: NSImage?

    func clear() {
        screenshot = nil
        selectedDeviceAndVariant = DeviceAndVariant(
            device: .iPhone16Pro,
            variant: Device.iPhone16Pro.variants[0]
        )
        candidates = []
        compositedImage = nil
    }

    func isSupportedScreenSize(_ size: CGSize) -> Bool {
        for device in Device.all {
            if size.equalTo(device.screenSize) {
                return true
            }
        }
        return false
    }

    func loadScreenshot(_ image: NSImage) throws {
        guard isSupportedScreenSize(image.size) else {
            throw AppError.unsupportedScreenshotSize
        }
        screenshot = image
    }

    func loadScreenshot(from url: URL, isSecurityScoped: Bool = false) throws {
        if isSecurityScoped {
            guard url.startAccessingSecurityScopedResource() else {
                print("Couldn't access security-scoped resource.")
                screenshot = nil
                compositedImage = nil
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            guard let screenshot = NSImage(contentsOf: url) else {
                print("Could not load image at \(url.absoluteString)")
                screenshot = nil
                compositedImage = nil
                return
            }

            guard isSupportedScreenSize(screenshot.size) else {
                throw AppError.unsupportedScreenshotSize
            }

            self.screenshot = screenshot
        } else {
            guard let screenshot = NSImage(contentsOf: url) else {
                print("Could not load image at \(url.absoluteString)")
                screenshot = nil
                compositedImage = nil
                return
            }

            guard isSupportedScreenSize(screenshot.size) else {
                throw AppError.unsupportedScreenshotSize
            }

            self.screenshot = screenshot
        }
    }

    func makeComposite() throws {
        guard let screenshot else {
            return
        }

        guard isSupportedScreenSize(screenshot.size) else {
            throw AppError.unsupportedScreenshotSize
        }

        candidates = DeviceAndVariant.all.compactMap { group in
            let filteredGroup = group.filter { deviceAndVariant in
                screenshot.size == deviceAndVariant.device.screenSize
            }
            return filteredGroup.isEmpty ? nil : filteredGroup
        }

        if !candidates.flatMap({ $0 }).contains(selectedDeviceAndVariant) {
            selectedDeviceAndVariant = candidates[0][0]
        }

        let device = selectedDeviceAndVariant.device

        guard let image = device.images[selectedDeviceAndVariant.variant] else {
            compositedImage = nil
            return
        }

        let content = Image(nsImage: image)
            .overlay(alignment: .topLeading) {
                Image(nsImage: screenshot)
                    .mask(
                        Image(nsImage: device.mask)
                    )
                    .offset(device.maskOffset)
            }

        compositedImage = ImageRenderer(content: content).nsImage

        if let compositedImage {
            copyImageToPasteboard(compositedImage)
        }
    }

    func copyImageToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
