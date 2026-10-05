//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum AppError: Error {
    case unsupportedScreenshotSize
    case unsupportedRecordingSize
    case droppedDevice(String)
    case unsupportedFile
    case exportFailed

    var message: String {
        switch self {
        case .unsupportedScreenshotSize:
            "Unsupported screenshot size"
        case .unsupportedRecordingSize:
            "Unsupported screen recording size"
        case .droppedDevice(let device):
            "\(device) screenshots are no longer supported"
        case .unsupportedFile:
            "Unsupported file"
        case .exportFailed:
            "Export failed"
        }
    }
}

/// A model and color, as chosen in the picker.
struct ModelColor: Hashable {
    let model: String
    let color: String
}

@MainActor @Observable class ContentModel {

    /// A screenshot or a screen recording.
    enum Source {
        case image(CGImage)
        case video(AVURLAsset)
    }

    private(set) var source: Source?

    var isVideo: Bool {
        if case .video = source {
            return true
        }
        return false
    }

    /// Bezels that fit the current screenshot, in catalog order.
    private(set) var candidates: [Bezel] = []

    private(set) var selection: Selection?

    /// The framed screenshot. For a recording, this is only set to a frozen
    /// frame while the recording is being cleared.
    var compositedImage: NSImage?

    /// Size of the framed output, which the window is fitted to.
    var compositeSize: CGSize? {
        selection?.bezel.canvasSize
    }

    // MARK: Recording State

    /// Frames the recording in the player and on export.
    private(set) var videoComposition: AVVideoComposition?

    private(set) var videoBackground: VideoBackground = .transparent

    /// The last solid color, kept while the background is transparent.
    private(set) var videoBackgroundColor = CGColor(gray: 1, alpha: 1)

    /// Plays the framed recording in a loop, muted.
    let player = AVPlayer()

    @ObservationIgnored private var compositionTask: Task<Void, Never>?
    @ObservationIgnored private var loopTask: Task<Void, Never>?

    /// A recording is read while it plays, so a security-scoped URL stays
    /// accessed until the recording is cleared.
    @ObservationIgnored private var securityScopedURL: URL?

    @ObservationIgnored private var bezelImages: [String: CGImage] = [:]
    @ObservationIgnored private var screenMasks: [String: CGImage] = [:]

    /// Sizes that only 1.x devices had, so a clearer message can be shown.
    private static let droppedDevices: [(portraitSize: CGSize, name: String)] = [
        (CGSize(width: 1170, height: 2532), "iPhone 14"),
        (CGSize(width: 1284, height: 2778), "iPhone 14 Plus")
    ]

    init() {
        player.isMuted = true
    }

    func clear() {
        compositionTask?.cancel()
        loopTask?.cancel()
        player.replaceCurrentItem(with: nil)
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        source = nil
        candidates = []
        selection = nil
        compositedImage = nil
        videoComposition = nil
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

    func setVideoBackground(_ background: VideoBackground) {
        videoBackground = background
        if case .color(let color) = background {
            videoBackgroundColor = color
        }
        makeComposite()
    }

    private func select(_ selection: Selection) {
        self.selection = selection
        makeComposite()
    }

    // MARK: - Loading

    func loadScreenshot(_ image: NSImage) throws {
        try setScreenshot(normalizeImageSizeTo1x(image))
    }

    /// Loads a screenshot or, for movie files, a screen recording.
    func load(from url: URL, isSecurityScoped: Bool = false) async throws {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .movie) == true {
            try await loadVideo(from: url, isSecurityScoped: isSecurityScoped)
        } else {
            try loadScreenshot(from: url, isSecurityScoped: isSecurityScoped)
        }
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
        let matches = Self.matchingBezels(for: size, allowScaling: false)

        guard let bezel = matches.first else {
            let portraitSize = size.width > size.height ? CGSize(width: size.height, height: size.width) : size
            if let device = Self.droppedDevices.first(where: { $0.portraitSize == portraitSize }) {
                throw AppError.droppedDevice(device.name)
            }
            throw AppError.unsupportedScreenshotSize
        }

        clear()
        source = .image(cgImage)
        candidates = matches
        let isRotated180 = bezel.pose.isLandscape && RotationDetector.detect(cgImage) == .rotated180
        select(Selection(bezel: bezel, isRotated180: isRotated180))
    }

    /// Picks the default bezel for a recording the same way as for a
    /// screenshot, detecting rotation from a frame near the start.
    private func loadVideo(from url: URL, isSecurityScoped: Bool) async throws {
        if isSecurityScoped {
            guard url.startAccessingSecurityScopedResource() else {
                print("Couldn't access security-scoped resource.")
                throw AppError.unsupportedFile
            }
        }

        let asset = AVURLAsset(url: url)
        let matches: [Bezel]
        let poster: CGImage?
        do {
            let size: CGSize
            do {
                size = try await VideoBezelComposer.displaySize(of: asset)
            } catch {
                print("Could not load video at \(url.absoluteString): \(error)")
                throw AppError.unsupportedFile
            }
            matches = Self.matchingBezels(for: size, allowScaling: true)
            guard !matches.isEmpty else {
                throw AppError.unsupportedRecordingSize
            }
            poster = await posterFrame(of: asset)
        } catch {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
            throw error
        }

        clear()
        securityScopedURL = isSecurityScoped ? url : nil
        source = .video(asset)
        candidates = matches

        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        loopTask = Task { [player] in
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification,
                object: item
            ) {
                await player.seek(to: .zero)
                player.play()
            }
        }

        // swiftlint:disable:next force_unwrapping
        let bezel = matches.first!
        let isRotated180 = bezel.pose.isLandscape
            && poster.map { RotationDetector.detect($0) == .rotated180 } == true
        select(Selection(bezel: bezel, isRotated180: isRotated180))
    }

    private func posterFrame(of asset: AVAsset) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let duration = (try? await asset.load(.duration)) ?? .zero
        let time = CMTimeMinimum(CMTime(seconds: 0.5, preferredTimescale: 600), CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2))
        return try? await generator.image(at: time).image
    }

    /// Bezels whose screen is exactly the given size, in catalog order.
    ///
    /// Screenshots are always native size. Recordings are often not (the
    /// iPhone's own screen recorder may downscale), so with `allowScaling`
    /// and no exact match, bezels with the same screen aspect ratio (within
    /// 1%) fit too.
    private static func matchingBezels(for size: CGSize, allowScaling: Bool) -> [Bezel] {
        let exact = BezelCatalog.all.filter { $0.screenshotSize == size }
        guard exact.isEmpty, allowScaling, size.width > 0, size.height > 0 else {
            return exact
        }
        let aspect = size.width / size.height
        return BezelCatalog.all.filter { bezel in
            let screen = bezel.screenshotSize
            return abs(screen.width / screen.height - aspect) / aspect < 0.01
        }
    }

    // MARK: - Compositing

    private func makeComposite() {
        switch source {
        case .image(let screenshotImage):
            makeImageComposite(screenshotImage)
        case .video(let asset):
            makeVideoComposition(asset)
        case nil:
            compositedImage = nil
        }
    }

    private func makeImageComposite(_ screenshotImage: CGImage) {
        guard let selection,
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

    /// Builds the composition in the background. A newer selection or
    /// background cancels an older build. Playback starts once the first
    /// composition is ready.
    private func makeVideoComposition(_ asset: AVURLAsset) {
        compositionTask?.cancel()
        guard let selection,
              let bezelImage = bezelImage(for: selection.bezel),
              let screenMask = screenMask(for: selection.bezel, bezelImage: bezelImage) else {
            videoComposition = nil
            return
        }
        let background = videoBackground
        compositionTask = Task {
            do {
                let composition = try await VideoBezelComposer.makeComposition(
                    asset: asset,
                    selection: selection,
                    bezelImage: bezelImage,
                    screenMask: screenMask,
                    background: background
                )
                guard !Task.isCancelled else {
                    return
                }
                let isFirst = videoComposition == nil
                videoComposition = composition
                player.currentItem?.videoComposition = composition
                if isFirst {
                    player.play()
                }
            } catch {
                print("Could not make video composition: \(error)")
            }
        }
    }

    /// Replaces the playing recording with a still of the current frame, so
    /// the clear effect (a SwiftUI shader) can be applied to it.
    func freezeVideoFrame() async {
        guard case .video(let asset) = source, let videoComposition else {
            return
        }
        player.pause()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if let image = try? await generator.image(at: player.currentTime()).image {
            compositedImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    // MARK: - Export

    func exportVideo(to url: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard case .video(let asset) = source, let videoComposition else {
            throw AppError.exportFailed
        }
        try await VideoExporter.export(
            asset: asset,
            composition: videoComposition,
            background: videoBackground,
            to: url,
            progress: progress
        )
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
