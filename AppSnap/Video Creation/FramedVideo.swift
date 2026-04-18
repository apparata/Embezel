import AppKit
import AVFoundation
import CGMath

enum FramedVideoError: Error {
    case missingVideoTrack
    case assetInsertionFailed(Error)
    case exportSessionCreationFailed
    case exportFailed(Error?)
    case unknown
}

extension FramedVideoError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "No video track found in the original asset."
        case .assetInsertionFailed(let error):
            return "Failed to insert video track: \(error.localizedDescription)"
        case .exportSessionCreationFailed:
            return "Unable to create export session."
        case .exportFailed(let error):
            return error?.localizedDescription ?? "Export failed with an unknown error."
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

@MainActor
func createFramedVideo(
    originalVideoURL: URL,
    backgroundImage: NSImage,
    maskImage: NSImage,
    outputURL: URL,
    videoOffset: CGPoint
) async throws -> URL {
    let asset = AVAsset(url: originalVideoURL)
    let composition = AVMutableComposition()

    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard let videoTrack = videoTracks.first else {
        throw FramedVideoError.missingVideoTrack
    }

    let duration = try await asset.load(.duration)
    let videoSize = try await videoTrack.load(.naturalSize)

    guard let videoCompositionTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        throw FramedVideoError.unknown
    }

    do {
        try videoCompositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
    } catch {
        throw FramedVideoError.assetInsertionFailed(error)
    }

    let scale: CGFloat = 0.5
    let renderSize = backgroundImage.size * scale

    let videoLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

    let scaledSize = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
    let position = videoOffset * scale

    let transform = CGAffineTransform.identity
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: position.x, y: position.y)
    videoLayerInstruction.setTransform(transform, at: .zero)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    instruction.layerInstructions = [videoLayerInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.instructions = [instruction]
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.renderSize = renderSize

    let parentLayer = CALayer()
    let videoLayer = CALayer()
    let backgroundLayer = CALayer()

    parentLayer.frame = CGRect(origin: .zero, size: renderSize)
    videoLayer.frame = CGRect(origin: position, size: scaledSize)

    if let cgBackground = backgroundImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        backgroundLayer.contents = cgBackground
    }
    backgroundLayer.frame = CGRect(origin: .zero, size: renderSize)

    // Apply mask to video layer
    if let cgMask = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let maskLayer = CALayer()
        maskLayer.contents = cgMask
        maskLayer.frame = CGRect(origin: position, size: scaledSize)
        //maskLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        videoLayer.mask = maskLayer
    }

    parentLayer.addSublayer(backgroundLayer)
    parentLayer.addSublayer(videoLayer)

    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer,
        in: parentLayer
    )

    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHEVC1920x1080) else {
        throw FramedVideoError.exportSessionCreationFailed
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.videoComposition = videoComposition
    exportSession.shouldOptimizeForNetworkUse = false

    if #available(macOS 15, *) {
        let states = exportSession.states(updateInterval: 1)
        Task.detached {
            for await state in states {
                switch state {
                case .pending, .waiting:
                    break

                case let .exporting(progress):
                    print(progress.fractionCompleted)

                @unknown default:
                    break
                }
            }
        }
    }

    return try await withCheckedThrowingContinuation { continuation in
        let session = exportSession
        session.exportAsynchronously {
            switch session.status {
            case .completed:
                print("Done!")
                continuation.resume(returning: outputURL)
            case .failed, .cancelled:
                continuation.resume(throwing: FramedVideoError.exportFailed(session.error))
            default:
                continuation.resume(throwing: FramedVideoError.unknown)
            }
        }
    }
}

extension AVAssetExportSession: @unchecked @retroactive Sendable {
    // Kludge
}
