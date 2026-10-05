//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AVFoundation
import UniformTypeIdentifiers

/// Writes a framed recording to a movie file. Audio is passed through.
enum VideoExporter {

    /// Transparent recordings are HEVC with alpha in a QuickTime movie;
    /// recordings on a solid background are plain HEVC in an MPEG-4 file.
    static func contentType(for background: VideoBackground) -> UTType {
        background.isTransparent ? .quickTimeMovie : .mpeg4Movie
    }

    /// Exports and reports progress (0...1) on the main actor. Cancelling
    /// the calling task cancels the export.
    static func export(
        asset: AVAsset,
        composition: AVVideoComposition,
        background: VideoBackground,
        to url: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let preset = background.isTransparent
            ? AVAssetExportPresetHEVCHighestQualityWithAlpha
            : AVAssetExportPresetHEVCHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw AppError.exportFailed
        }
        session.videoComposition = composition
        session.outputURL = url
        session.outputFileType = background.isTransparent ? .mov : .mp4

        // The save panel has already confirmed replacing an existing file.
        try? FileManager.default.removeItem(at: url)

        let box = SessionBox(session)
        let poller = Task { @MainActor in
            while !Task.isCancelled {
                progress(Double(box.session.progress))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer {
            poller.cancel()
        }

        await withTaskCancellationHandler {
            await box.session.export()
        } onCancel: {
            box.session.cancelExport()
        }

        switch session.status {
        case .completed:
            await progress(1)
        case .cancelled:
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        default:
            if let error = session.error {
                print("Export failed: \(error)")
            }
            try? FileManager.default.removeItem(at: url)
            throw AppError.exportFailed
        }
    }

    /// The export session isn't Sendable, but its progress and cancellation
    /// are safe to use from any thread.
    private final class SessionBox: @unchecked Sendable {
        let session: AVAssetExportSession

        init(_ session: AVAssetExportSession) {
            self.session = session
        }
    }
}
