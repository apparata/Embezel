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

// MARK: - Matching

enum BezelMatching {

    /// Sizes that only 1.x devices had, so a clearer message can be shown.
    private static let droppedDevices: [(portraitSize: CGSize, name: String)] = [
        (CGSize(width: 1170, height: 2532), "iPhone 14"),
        (CGSize(width: 1284, height: 2778), "iPhone 14 Plus")
    ]

    /// Bezels whose screen is exactly the given size, in catalog order.
    ///
    /// Screenshots are always native size. Recordings are often not (the
    /// iPhone's own screen recorder may downscale), so with `allowScaling`
    /// and no exact match, bezels with the same screen aspect ratio (within
    /// 1%) fit too.
    static func bezels(for size: CGSize, allowScaling: Bool) -> [Bezel] {
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

    /// The 1.x device a screenshot of this size came from, if any.
    static func droppedDevice(for size: CGSize) -> String? {
        let portraitSize = size.width > size.height ? CGSize(width: size.height, height: size.width) : size
        return droppedDevices.first { $0.portraitSize == portraitSize }?.name
    }
}

// MARK: - Choices

/// The models, colors and poses offered for a set of candidate bezels.
struct BezelChoices {

    let candidates: [Bezel]

    /// Models, newest first.
    var models: [String] {
        candidates.map(\.model).uniqued()
    }

    func colors(for model: String) -> [String] {
        candidates.filter { $0.model == model }.map(\.color).uniqued()
    }

    func poses(for modelColor: ModelColor) -> [Pose] {
        candidates
            .filter { $0.model == modelColor.model && $0.color == modelColor.color }
            .map(\.pose)
            .uniqued()
    }

    /// The bezel for a model and color, preferring the given pose and
    /// otherwise taking the first pose that fits.
    func bezel(for modelColor: ModelColor, preferring pose: Pose?) -> Bezel? {
        let matching = candidates.filter { $0.model == modelColor.model && $0.color == modelColor.color }
        return matching.first { $0.pose == pose } ?? matching.first
    }
}

/// A model and color, as chosen in the picker.
struct ModelColor: Hashable {
    let model: String
    let color: String
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
