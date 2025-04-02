//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit

@MainActor @Observable class ContentModel {

    var screenshot: NSImage?
    var device: Device = .iPhone16Pro
    var variant: String = Device.iPhone16Pro.variants[0]

    var compositedImage: NSImage?

    func clear() {
        screenshot = nil
        device = .iPhone16Pro
        compositedImage = nil
    }

    func loadScreenshot(_ image: NSImage) {
        screenshot = image
    }

    func loadScreenshot(from url: URL, isSecurityScoped: Bool = false) {
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

            self.screenshot = screenshot
        } else {
            guard let screenshot = NSImage(contentsOf: url) else {
                print("Could not load image at \(url.absoluteString)")
                screenshot = nil
                compositedImage = nil
                return
            }

            self.screenshot = screenshot
        }
    }

    func makeComposite() {
        guard let screenshot else {
            return
        }

        let device: Device? = switch screenshot.size {
        case Device.iPhone16Pro.screenSize: .iPhone16Pro
        case Device.iPhone16ProMax.screenSize: .iPhone16ProMax
        default: nil
        }

        guard let device else {
            return
        }

        if !device.variants.contains(variant) {
            variant = device.variants[0]
        }

        self.device = device

        guard let image = device.images[variant] else {
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
