//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import CoreGraphics

/// Guesses which way a landscape screenshot was taken, i.e. on which side
/// the Dynamic Island was.
///
/// EXPERIMENTAL: screenshots contain no pixels of the island itself, and
/// iOS landscape safe-area insets are symmetric, so there is usually no
/// signal. The only case handled is a clearly asymmetric layout: one edge
/// strip that is a single flat color (content kept away from the island)
/// while the other edge strip has content. Everything else is `.unknown`.
/// The threshold is conservative and has not been tuned against real
/// screenshots.
enum RotationDetector {

    enum Guess {
        /// Island on the left, as in the landscape bezel images.
        case asShipped
        /// Island on the right; the bezel needs to be rotated 180°.
        case rotated180
        case unknown
    }

    /// Width of each edge strip, as a fraction of the screenshot width.
    /// About 60 pt at 3x on a 6.3" phone.
    private static let stripFraction = 0.07

    /// A strip counts as empty when at least this fraction of its pixels
    /// match its dominant color.
    private static let emptyThreshold = 0.995

    /// The opposite strip must have at most this fraction of matching pixels.
    private static let busyThreshold = 0.85

    static func detect(_ screenshot: CGImage) -> Guess {
        guard screenshot.width > screenshot.height else {
            return .unknown
        }

        // Analyze a downscaled copy; the signal is coarse.
        let width = max(screenshot.width / 4, 1)
        let height = max(screenshot.height / 4, 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ),
              let data = context.data else {
            return .unknown
        }
        context.interpolationQuality = .low
        context.draw(screenshot, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let stripWidth = max(Int(Double(width) * stripFraction), 1)
        let left = uniformity(pixels, width: width, height: height, columns: 0..<stripWidth)
        let right = uniformity(pixels, width: width, height: height, columns: (width - stripWidth)..<width)

        if left >= emptyThreshold && right <= busyThreshold {
            return .asShipped
        }
        if right >= emptyThreshold && left <= busyThreshold {
            return .rotated180
        }
        return .unknown
    }

    /// Fraction of pixels in the columns that are close to the most common
    /// (quantized) color in those columns.
    private static func uniformity(
        _ pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        columns: Range<Int>
    ) -> Double {
        func quantized(_ index: Int) -> Int {
            Int(pixels[index] >> 3) << 10 | Int(pixels[index + 1] >> 3) << 5 | Int(pixels[index + 2] >> 3)
        }

        var counts: [Int: Int] = [:]
        for y in 0..<height {
            for x in columns {
                counts[quantized((y * width + x) * 4), default: 0] += 1
            }
        }
        guard let dominant = counts.max(by: { $0.value < $1.value }) else {
            return 0
        }
        return Double(dominant.value) / Double(columns.count * height)
    }
}
