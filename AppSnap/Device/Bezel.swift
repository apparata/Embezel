//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import CoreGraphics

// MARK: - Pose

enum Pose: String, CaseIterable {
    case portrait
    case landscape
    case outerClosedPortrait
    case outerClosedLandscape
    case outerOpen
    case innerOpenPortrait
    case innerOpenLandscape

    /// Name as used in bezel file names, e.g. "Outer Closed Portrait".
    var displayName: String {
        switch self {
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        case .outerClosedPortrait: "Outer Closed Portrait"
        case .outerClosedLandscape: "Outer Closed Landscape"
        case .outerOpen: "Outer Open"
        case .innerOpenPortrait: "Inner Open Portrait"
        case .innerOpenLandscape: "Inner Open Landscape"
        }
    }

    /// Short name for choosing between poses that fit the same screenshot.
    var shortName: String {
        switch self {
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        case .outerClosedPortrait, .outerClosedLandscape: "Closed"
        case .outerOpen, .innerOpenPortrait, .innerOpenLandscape: "Open"
        }
    }

    var isLandscape: Bool {
        switch self {
        case .landscape, .outerClosedLandscape, .innerOpenLandscape: true
        case .portrait, .outerClosedPortrait, .outerOpen, .innerOpenPortrait: false
        }
    }
}

// MARK: - Bezel

/// A device bezel image and the position of its screen.
///
/// All geometry is in pixels with a top-left origin, as in the source PSDs.
/// The bezel image has a transparent screen hole; the screenshot is drawn
/// underneath it, so the bezel's own pixels (including the Dynamic Island)
/// do the clipping.
struct Bezel: Hashable {
    let model: String
    let color: String
    let pose: Pose
    let imageName: String
    let canvasSize: CGSize
    let screenRect: CGRect

    /// Pixel size of a screenshot that fits this bezel.
    var screenshotSize: CGSize {
        screenRect.size
    }
}

// MARK: - Selection

struct Selection: Hashable {
    let bezel: Bezel

    /// Rotates the bezel by 180°, which puts the Dynamic Island on the other
    /// side. Only applies to landscape poses.
    let isRotated180: Bool

    init(bezel: Bezel, isRotated180: Bool = false) {
        self.bezel = bezel
        self.isRotated180 = isRotated180 && bezel.pose.isLandscape
    }

    /// Screen rectangle in pixels with a top-left origin, after rotation.
    var screenRect: CGRect {
        let rect = bezel.screenRect
        guard isRotated180 else {
            return rect
        }
        return CGRect(
            x: bezel.canvasSize.width - rect.maxX,
            y: bezel.canvasSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// File name for exporting and dragging, without extension.
    var fileName: String {
        "\(bezel.model) - \(bezel.color) - \(bezel.pose.displayName)"
    }
}
