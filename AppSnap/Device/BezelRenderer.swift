//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import CoreGraphics

enum BezelRenderer {

    /// Draws the screenshot 1:1 into the screen rectangle, clipped by the
    /// screen mask, and the bezel on top of it. The output has the bezel's
    /// canvas size and keeps the screenshot's color space (iPhone
    /// screenshots are usually Display P3).
    static func render(
        screenshot: CGImage,
        bezelImage: CGImage,
        screenMask: CGImage,
        selection: Selection
    ) -> CGImage? {
        let canvas = selection.bezel.canvasSize
        let canvasRect = CGRect(origin: .zero, size: canvas)

        let colorSpace = screenshot.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace, let context = CGContext(
            data: nil,
            width: Int(canvas.width),
            height: Int(canvas.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high

        // The mask belongs to the unrotated bezel, so it is applied under
        // the same rotation as the bezel. The screenshot itself is never
        // rotated.
        context.saveGState()
        if selection.isRotated180 {
            rotate180(context, canvas: canvas)
        }
        context.clip(to: canvasRect, mask: screenMask)
        if selection.isRotated180 {
            rotate180(context, canvas: canvas)
        }

        // Core Graphics has a bottom-left origin; the geometry is top-left.
        let screen = selection.screenRect
        context.draw(screenshot, in: CGRect(
            x: screen.minX,
            y: canvas.height - screen.maxY,
            width: screen.width,
            height: screen.height
        ))
        context.restoreGState()

        if selection.isRotated180 {
            rotate180(context, canvas: canvas)
        }
        context.draw(bezelImage, in: canvasRect)

        return context.makeImage()
    }

    /// Makes a grayscale mask for the unrotated bezel that is white inside
    /// the screen rectangle, except where the bezel is transparent because
    /// it is outside the device.
    ///
    /// The screen rectangle's corners stick out beyond the device's rounded
    /// outer corners, so the screenshot must not be drawn there. "Outside"
    /// is every pixel that is not fully opaque and can be reached from the
    /// canvas border without crossing a fully opaque pixel. The transparent
    /// screen hole is enclosed by the opaque frame, so it is never reached.
    static func makeScreenMask(bezelImage: CGImage, bezel: Bezel) -> CGImage? {
        let width = bezelImage.width
        let height = bezelImage.height
        guard width == Int(bezel.canvasSize.width), height == Int(bezel.canvasSize.height) else {
            return nil
        }

        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = alpha.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else {
                return false
            }
            context.draw(bezelImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }

        // Row 0 of the buffer is the top row, matching the top-left geometry.
        var mask = [UInt8](repeating: 0, count: width * height)
        alpha.withUnsafeBufferPointer { alpha in
            mask.withUnsafeMutableBufferPointer { mask in
                let screen = bezel.screenRect
                for y in Int(screen.minY)..<Int(screen.maxY) {
                    for x in Int(screen.minX)..<Int(screen.maxX) {
                        mask[y * width + x] = 255
                    }
                }

                // Flood fill the outside from the canvas border. Filled
                // pixels are marked by clearing the mask and setting a
                // separate visited flag.
                var visited = [Bool](repeating: false, count: width * height)
                var stack: [Int] = []
                stack.reserveCapacity(4096)
                func push(_ index: Int) {
                    if !visited[index] && alpha[index] < 255 {
                        visited[index] = true
                        stack.append(index)
                    }
                }
                for x in 0..<width {
                    push(x)
                    push((height - 1) * width + x)
                }
                for y in 0..<height {
                    push(y * width)
                    push(y * width + width - 1)
                }
                while let index = stack.popLast() {
                    mask[index] = 0
                    let x = index % width
                    if x > 0 { push(index - 1) }
                    if x < width - 1 { push(index + 1) }
                    if index >= width { push(index - width) }
                    if index < (height - 1) * width { push(index + width) }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(mask) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func rotate180(_ context: CGContext, canvas: CGSize) {
        context.translateBy(x: canvas.width, y: canvas.height)
        context.rotate(by: .pi)
    }
}
