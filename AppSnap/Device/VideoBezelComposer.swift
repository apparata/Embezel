//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AVFoundation
import CoreImage

// MARK: - Video Background

enum VideoBackground: Hashable {
    /// Transparent outside the device, exported as HEVC with alpha.
    case transparent
    /// A solid color outside the device.
    case color(CGColor)

    var isTransparent: Bool {
        self == .transparent
    }
}

// MARK: - Video Bezel Composer

/// The video counterpart of `BezelRenderer`: frames each video frame in the
/// bezel with Core Image.
///
/// Unlike screenshots, recordings are not always at the device's native
/// resolution (on-device screen recordings are often downscaled), so each
/// frame is scaled to fill the screen rectangle.
enum VideoBezelComposer {

    static func makeComposition(
        asset: AVAsset,
        selection: Selection,
        bezelImage: CGImage,
        screenMask: CGImage,
        background: VideoBackground
    ) async throws -> AVVideoComposition {
        let canvas = selection.bezel.canvasSize
        let canvasRect = CGRect(origin: .zero, size: canvas)

        // The mask belongs to the unrotated bezel, so both are rotated
        // together. Core Image has a bottom-left origin, but a 180° turn
        // about the canvas center is the same in either convention.
        var bezel = CIImage(cgImage: bezelImage)
        var mask = CIImage(cgImage: screenMask)
        if selection.isRotated180 {
            let rotation = CGAffineTransform(translationX: canvas.width, y: canvas.height).rotated(by: .pi)
            bezel = bezel.transformed(by: rotation)
            mask = mask.transformed(by: rotation)
        }

        // Core Image has a bottom-left origin; the geometry is top-left.
        let screen = selection.screenRect
        let screenRect = CGRect(
            x: screen.minX,
            y: canvas.height - screen.maxY,
            width: screen.width,
            height: screen.height
        )

        let backdrop: CIImage? = switch background {
        case .transparent: nil
        case .color(let color): CIImage(color: CIColor(cgColor: color)).cropped(to: canvasRect)
        }

        let orientation = try await displayOrientation(of: asset)

        let composition = try await AVMutableVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                let frame = orientation.upright(request.sourceImage)
                let framed = mask.blendMask(
                    frame: fill(frame, into: screenRect),
                    bezel: bezel
                )
                let output = backdrop.map { framed.composited(over: $0) } ?? framed
                request.finish(with: output.cropped(to: canvasRect), context: nil)
            }
        )

        // Video encoders want even dimensions; the extra pixel is empty.
        composition.renderSize = CGSize(
            width: (canvas.width / 2).rounded(.up) * 2,
            height: (canvas.height / 2).rounded(.up) * 2
        )
        composition.colorPrimaries = AVVideoColorPrimaries_P3_D65
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return composition
    }

    /// Size of the video track as displayed, with its preferred transform
    /// applied.
    static func displaySize(of asset: AVAsset) async throws -> CGSize {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.unsupportedFile
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let size = naturalSize.applying(transform)
        return CGSize(width: abs(size.width).rounded(), height: abs(size.height).rounded())
    }

    // MARK: - Frame Placement

    /// Scales the frame to fill the rectangle, centered, and crops off any
    /// overflow. Native-size frames are placed 1:1.
    private static func fill(_ frame: CIImage, into rect: CGRect) -> CIImage {
        let extent = frame.extent
        guard extent.width > 0, extent.height > 0 else {
            return frame
        }
        let scale = max(rect.width / extent.width, rect.height / extent.height)
        let size = CGSize(width: extent.width * scale, height: extent.height * scale)
        let transform = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2
            ))
        return frame
            .transformed(by: transform, highQualityDownsample: true)
            .cropped(to: rect)
    }

    // MARK: - Orientation

    /// Recordings with a rotated preferred transform need their frames
    /// turned upright. Whether the filter handler's source image already has
    /// the transform applied isn't documented clearly, so frames are only
    /// turned when their size is the display size swapped.
    private struct Orientation {
        let displaySize: CGSize
        let orientation: CGImagePropertyOrientation

        init(displaySize: CGSize, transform: CGAffineTransform) {
            self.displaySize = displaySize
            orientation = switch (transform.a, transform.b, transform.c, transform.d) {
            case (0, 1, -1, 0): .right
            case (0, -1, 1, 0): .left
            case (-1, 0, 0, -1): .down
            default: .up
            }
        }

        func upright(_ image: CIImage) -> CIImage {
            let extent = image.extent
            let isSwapped = displaySize.width != displaySize.height
                && abs(extent.width - displaySize.height) < 1
                && abs(extent.height - displaySize.width) < 1
            guard isSwapped, orientation != .up else {
                return image
            }
            return image.oriented(orientation)
        }
    }

    private static func displayOrientation(of asset: AVAsset) async throws -> Orientation {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.unsupportedFile
        }
        let transform = try await track.load(.preferredTransform)
        return Orientation(displaySize: try await displaySize(of: asset), transform: transform)
    }
}

// MARK: - Masking

private extension CIImage {

    /// Treats `self` as the screen mask: keeps the frame where the mask is
    /// white and draws the bezel on top.
    func blendMask(frame: CIImage, bezel: CIImage) -> CIImage {
        let masked = frame.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: self
        ])
        return bezel.composited(over: masked)
    }
}
