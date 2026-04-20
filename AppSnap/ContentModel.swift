//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit
import CollectionKit
import AVFoundation

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
        let normalizedImage = normalizeImageSizeTo1x(image)
        guard isSupportedScreenSize(normalizedImage.size) else {
            throw AppError.unsupportedScreenshotSize
        }
        screenshot = normalizedImage
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

            let normalizedScreenshot = normalizeImageSizeTo1x(screenshot)

            guard isSupportedScreenSize(normalizedScreenshot.size) else {
                throw AppError.unsupportedScreenshotSize
            }

            self.screenshot = normalizedScreenshot
        } else {
            guard let screenshot = NSImage(contentsOf: url) else {
                print("Could not load image at \(url.absoluteString)")
                screenshot = nil
                compositedImage = nil
                return
            }

            let normalizedScreenshot = normalizeImageSizeTo1x(screenshot)

            guard isSupportedScreenSize(normalizedScreenshot.size) else {
                throw AppError.unsupportedScreenshotSize
            }

            self.screenshot = normalizedScreenshot
        }
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

    @MainActor
    func makeVideo(from inputVideoURL: URL) async throws {

        _ = inputVideoURL.startAccessingSecurityScopedResource()
        defer { inputVideoURL.stopAccessingSecurityScopedResource() }

        let videoSize = try await getVideoDimensions(from: inputVideoURL)

        guard isSupportedScreenSize(videoSize) else {
            throw AppError.unsupportedScreenshotSize
        }

        candidates = DeviceAndVariant.all.compactMap { group in
            let filteredGroup = group.filter { deviceAndVariant in
                videoSize == deviceAndVariant.device.screenSize
            }
            return filteredGroup.isEmpty ? nil : filteredGroup
        }

        if !candidates.flatMap({ $0 }).contains(selectedDeviceAndVariant) {
            selectedDeviceAndVariant = candidates[0][0]
        }

        let device = selectedDeviceAndVariant.device

        guard let image = device.images[selectedDeviceAndVariant.variant] else {
            return
        }

        let outputURL = try await createFramedVideo(
            originalVideoURL: inputVideoURL,
            backgroundImage: image,
            maskImage: device.mask,
            outputURL: makeTemporaryOutputURL(),
            videoOffset: CGPoint(x: device.maskOffset.width, y: device.maskOffset.height)
        )

        NSWorkspace().open(outputURL.deletingLastPathComponent())
    }

    private func makeTemporaryOutputURL(extension fileExtension: String = "mp4") -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + "." + fileExtension
        return tempDirectory.appendingPathComponent(fileName)
    }

    private func getVideoDimensions(from url: URL) async throws -> CGSize {
        let asset = AVAsset(url: url)

        // Wait until the asset is ready (in case it's loaded asynchronously)
        let tracks = try await asset.loadTracks(withMediaType: .video)

        // Get the first video track
        guard let videoTrack = tracks.first else {
            throw AppError.unsupportedScreenshotSize
        }

        let videoSize = try await videoTrack.load(.naturalSize)
        return videoSize
    }

}
