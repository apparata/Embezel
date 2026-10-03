#!/usr/bin/env swift
//
//  Copyright © 2026 Apparata AB. All rights reserved.
//
//  Imports device bezels into the app.
//
//  Usage: swift scripts/import-bezels.swift <path-to-Bezels>
//
//  The source folder is expected to look like this:
//
//      <Family>/Photoshop/**/<Model> - <Color> - <Pose>.psd
//      <Family>/PNG/**/<Model> - <Color> - <Pose>.png
//
//  The screen rectangle of each bezel is read from the bounds of the layer
//  named "Screen" in the PSD. The PNG is copied unchanged into
//  AppSnap/Assets.xcassets/Bezels/ and the geometry is written to
//  AppSnap/Device/BezelCatalog.swift.
//
//  Everything is validated before anything is written. If any file fails,
//  the script exits with an error and leaves the repository untouched.
//

import Foundation
import CoreGraphics
import ImageIO

// MARK: - Configuration

/// Models, newest first. Drives the picker section order and the default
/// selection when several models match a screenshot. Every imported model
/// must be listed here.
let modelOrder = [
    "iPhone 18 Pro Max",
    "iPhone 18 Pro",
    "iPhone Duo",
    "iPhone 17 Pro Max",
    "iPhone 17 Pro",
    "iPhone Air",
    "iPhone 17",
    "iPhone 16 Pro Max",
    "iPhone 16 Pro",
    "iPhone 16 Plus",
    "iPhone 16"
]

/// Pose names as they appear in file names, mapped to `Pose` case names.
/// The order here is the pose order in the generated catalog.
let poses: [(fileName: String, caseName: String)] = [
    ("Portrait", "portrait"),
    ("Landscape", "landscape"),
    ("Outer Closed Portrait", "outerClosedPortrait"),
    ("Outer Closed Landscape", "outerClosedLandscape"),
    ("Outer Open", "outerOpen"),
    ("Inner Open Portrait", "innerOpenPortrait"),
    ("Inner Open Landscape", "innerOpenLandscape")
]

// MARK: - Errors

struct ImportError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}

// MARK: - PSD Parsing

struct PSDInfo {
    let canvasSize: (width: Int, height: Int)
    let screenRect: (x: Int, y: Int, width: Int, height: Int)
}

/// Big-endian reader over a file handle. Only reads the header and the
/// layer records; pixel data is never touched.
final class Reader {

    private let handle: FileHandle

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
    }

    deinit {
        try? handle.close()
    }

    var offset: UInt64 {
        (try? handle.offset()) ?? 0
    }

    func seek(to offset: UInt64) throws {
        try handle.seek(toOffset: offset)
    }

    func skip(_ count: UInt64) throws {
        try seek(to: offset + count)
    }

    func bytes(_ count: Int) throws -> Data {
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw ImportError("Unexpected end of file")
        }
        return data
    }

    func uint(_ size: Int) throws -> UInt64 {
        try bytes(size).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    func int32() throws -> Int {
        Int(Int32(bitPattern: UInt32(try uint(4))))
    }

    func int16() throws -> Int {
        Int(Int16(bitPattern: UInt16(try uint(2))))
    }

    func string(_ count: Int) throws -> String {
        String(decoding: try bytes(count), as: UTF8.self)
    }
}

/// Keys of additional layer information blocks that use 8-byte lengths in
/// PSB (version 2) files.
let longLengthKeys: Set<String> = [
    "LMsk", "Lr16", "Lr32", "Layr", "Mt16", "Mt32", "Mtrn", "Alph",
    "FMsk", "lnk2", "FEid", "FXid", "PxSD"
]

func readPSD(at url: URL) throws -> PSDInfo {
    let reader = try Reader(url: url)

    guard try reader.string(4) == "8BPS" else {
        throw ImportError("Not a Photoshop file")
    }
    let version = try reader.uint(2)
    guard version == 1 || version == 2 else {
        throw ImportError("Unsupported PSD version \(version)")
    }
    let isBig = version == 2
    try reader.skip(6) // Reserved
    _ = try reader.uint(2) // Channels
    let height = Int(try reader.uint(4))
    let width = Int(try reader.uint(4))
    try reader.skip(4) // Depth, color mode

    try reader.skip(try reader.uint(4)) // Color mode data
    try reader.skip(try reader.uint(4)) // Image resources

    let layerAndMaskLength = try reader.uint(isBig ? 8 : 4)
    guard layerAndMaskLength > 0 else {
        throw ImportError("No layers")
    }
    _ = try reader.uint(isBig ? 8 : 4) // Layer info length
    let layerCount = abs(try reader.int16())

    var screenRects: [(x: Int, y: Int, width: Int, height: Int)] = []

    for _ in 0..<layerCount {
        let top = try reader.int32()
        let left = try reader.int32()
        let bottom = try reader.int32()
        let right = try reader.int32()
        let channelCount = try reader.uint(2)
        try reader.skip(channelCount * (isBig ? 10 : 6))
        try reader.skip(12) // Blend signature, blend mode, opacity, clipping, flags, filler
        let extraLength = try reader.uint(4)
        let extraEnd = reader.offset + extraLength
        try reader.skip(try reader.uint(4)) // Layer mask data
        try reader.skip(try reader.uint(4)) // Blending ranges
        let nameLength = Int(try reader.uint(1))
        var name = String(decoding: try reader.bytes(nameLength), as: UTF8.self)
        let padding = (4 - (nameLength + 1) % 4) % 4
        try reader.skip(UInt64(padding))

        // Prefer the Unicode name from the additional layer information.
        while reader.offset + 12 <= extraEnd {
            let signature = try reader.string(4)
            guard signature == "8BIM" || signature == "8B64" else {
                break
            }
            let key = try reader.string(4)
            let length = try reader.uint(isBig && longLengthKeys.contains(key) ? 8 : 4)
            let blockEnd = reader.offset + length
            if key == "luni" {
                let characterCount = Int(try reader.uint(4))
                let data = try reader.bytes(characterCount * 2)
                name = String(decoding: stride(from: 0, to: data.count, by: 2).map {
                    UInt16(data[data.startIndex + $0]) << 8 | UInt16(data[data.startIndex + $0 + 1])
                }, as: UTF16.self)
            }
            try reader.seek(to: blockEnd)
        }
        try reader.seek(to: extraEnd)

        if name == "Screen" {
            screenRects.append((left, top, right - left, bottom - top))
        }
    }

    guard let screenRect = screenRects.first else {
        throw ImportError("No layer named \"Screen\"")
    }
    guard screenRects.count == 1 else {
        throw ImportError("More than one layer named \"Screen\"")
    }
    guard screenRect.width > 0, screenRect.height > 0 else {
        throw ImportError("The \"Screen\" layer is empty")
    }
    return PSDInfo(canvasSize: (width, height), screenRect: screenRect)
}

// MARK: - PNG Checks

func pngSize(at url: URL) throws -> (width: Int, height: Int) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        throw ImportError("Could not read PNG")
    }
    return (width, height)
}

func pngAlpha(at url: URL, x: Int, y: Int) throws -> UInt8 {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
        throw ImportError("Could not decode PNG")
    }
    var alpha: UInt8 = 0
    guard let context = CGContext(
        data: &alpha,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 1,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
    ) else {
        throw ImportError("Could not create bitmap context")
    }
    context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return alpha
}

// MARK: - Import

struct Entry {
    let model: String
    let color: String
    let pose: (fileName: String, caseName: String)
    let name: String
    let png: URL
    let info: PSDInfo
}

func files(withExtension pathExtension: String, under directory: URL) -> [URL] {
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
    var urls: [URL] = []
    while let url = enumerator?.nextObject() as? URL {
        if url.pathExtension.lowercased() == pathExtension {
            urls.append(url)
        }
    }
    return urls
}

func parseName(_ name: String) throws -> (model: String, color: String, pose: (fileName: String, caseName: String)) {
    let parts = name.components(separatedBy: " - ")
    guard parts.count == 3 else {
        throw ImportError("File name is not \"<Model> - <Color> - <Pose>\"")
    }
    guard let pose = poses.first(where: { $0.fileName == parts[2] }) else {
        throw ImportError("Unknown pose \"\(parts[2])\"")
    }
    guard modelOrder.contains(parts[0]) else {
        throw ImportError("Model \"\(parts[0])\" is not in modelOrder in scripts/import-bezels.swift")
    }
    return (parts[0], parts[1], pose)
}

func collectEntries(source: URL) -> (entries: [Entry], errors: [String]) {
    var errors: [String] = []
    var entries: [Entry] = []

    let families = (try? FileManager.default.contentsOfDirectory(
        at: source,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )) ?? []

    var psds: [String: URL] = [:]
    var pngs: [String: URL] = [:]
    for family in families where (try? family.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        for url in files(withExtension: "psd", under: family.appendingPathComponent("Photoshop")) {
            let name = url.deletingPathExtension().lastPathComponent
            if psds[name] != nil {
                errors.append("\(name): more than one PSD with this name")
            }
            psds[name] = url
        }
        for url in files(withExtension: "png", under: family.appendingPathComponent("PNG")) {
            let name = url.deletingPathExtension().lastPathComponent
            if pngs[name] != nil {
                errors.append("\(name): more than one PNG with this name")
            }
            pngs[name] = url
        }
    }

    if psds.isEmpty {
        errors.append("No PSD files found under \(source.path)/<Family>/Photoshop/")
    }

    for name in pngs.keys.sorted() where psds[name] == nil {
        errors.append("\(name): PNG has no matching PSD")
    }

    for name in psds.keys.sorted() {
        guard let psd = psds[name] else {
            continue
        }
        guard let png = pngs[name] else {
            errors.append("\(name): PSD has no matching PNG")
            continue
        }
        do {
            let parsed = try parseName(name)
            let info = try readPSD(at: psd)
            let size = try pngSize(at: png)
            guard size == info.canvasSize else {
                throw ImportError("PNG is \(size.width)x\(size.height) but the PSD canvas is \(info.canvasSize.width)x\(info.canvasSize.height)")
            }
            let rect = info.screenRect
            let alpha = try pngAlpha(at: png, x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
            guard alpha == 0 else {
                throw ImportError("PNG is not transparent at the center of the screen")
            }
            entries.append(Entry(model: parsed.model, color: parsed.color, pose: parsed.pose, name: name, png: png, info: info))
        } catch {
            errors.append("\(name): \(error)")
        }
    }

    var seen: Set<String> = []
    for entry in entries {
        let key = "\(entry.model)|\(entry.color)|\(entry.pose.caseName)"
        if !seen.insert(key).inserted {
            errors.append("\(entry.name): duplicate model, color and pose")
        }
    }

    return (entries, errors)
}

func sorted(_ entries: [Entry]) -> [Entry] {
    entries.sorted { lhs, rhs in
        let lhsModel = modelOrder.firstIndex(of: lhs.model) ?? .max
        let rhsModel = modelOrder.firstIndex(of: rhs.model) ?? .max
        if lhsModel != rhsModel {
            return lhsModel < rhsModel
        }
        if lhs.color != rhs.color {
            return lhs.color < rhs.color
        }
        let lhsPose = poses.firstIndex { $0.caseName == lhs.pose.caseName } ?? .max
        let rhsPose = poses.firstIndex { $0.caseName == rhs.pose.caseName } ?? .max
        return lhsPose < rhsPose
    }
}

// MARK: - Output

func swiftString(_ string: String) -> String {
    "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

func makeCatalogSource(_ entries: [Entry], sourceName: String) -> String {
    var lines: [String] = [
        "//",
        "//  Generated by scripts/import-bezels.swift from \(sourceName). Do not edit.",
        "//",
        "",
        "import CoreGraphics",
        "",
        "enum BezelCatalog {",
        "",
        "    static let all: [Bezel] = ["
    ]
    for (index, entry) in entries.enumerated() {
        let rect = entry.info.screenRect
        let canvas = entry.info.canvasSize
        let separator = index == entries.count - 1 ? "" : ","
        lines.append("""
                Bezel(
                    model: \(swiftString(entry.model)),
                    color: \(swiftString(entry.color)),
                    pose: .\(entry.pose.caseName),
                    imageName: \(swiftString(entry.name)),
                    canvasSize: CGSize(width: \(canvas.width), height: \(canvas.height)),
                    screenRect: CGRect(x: \(rect.x), y: \(rect.y), width: \(rect.width), height: \(rect.height))
                )\(separator)
        """)
    }
    lines.append("    ]")
    lines.append("}")
    return lines.joined(separator: "\n") + "\n"
}

func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}

func writeAssetFolder(_ entries: [Entry], to folder: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    try json([
        "info": ["author": "xcode", "version": 1]
    ]).write(to: folder.appendingPathComponent("Contents.json"))
    for entry in entries {
        let imageSet = folder.appendingPathComponent("\(entry.name).imageset")
        try fileManager.createDirectory(at: imageSet, withIntermediateDirectories: true)
        let fileName = entry.png.lastPathComponent
        try fileManager.copyItem(at: entry.png, to: imageSet.appendingPathComponent(fileName))
        try json([
            "images": [["filename": fileName, "idiom": "universal"]],
            "info": ["author": "xcode", "version": 1]
        ]).write(to: imageSet.appendingPathComponent("Contents.json"))
    }
}

func replace(_ destination: URL, with replacement: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(destination, withItemAt: replacement)
    } else {
        try fileManager.moveItem(at: replacement, to: destination)
    }
}

func printSummary(_ entries: [Entry]) {
    func pad(_ string: String, _ width: Int) -> String {
        string.padding(toLength: max(width, string.count), withPad: " ", startingAt: 0)
    }
    print(pad("Model", 18) + pad("Color", 18) + pad("Pose", 24) + pad("Canvas", 12) + "Screen")
    for entry in entries {
        let canvas = entry.info.canvasSize
        let rect = entry.info.screenRect
        print(pad(entry.model, 18) + pad(entry.color, 18) + pad(entry.pose.fileName, 24)
              + pad("\(canvas.width)x\(canvas.height)", 12)
              + "(\(rect.x), \(rect.y)) \(rect.width)x\(rect.height)")
    }
}

// MARK: - Main

func main() -> Int32 {
    let arguments = CommandLine.arguments
    guard arguments.count == 2 else {
        print("Usage: swift scripts/import-bezels.swift <path-to-Bezels>")
        return 2
    }
    let source = URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath).standardizedFileURL
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let assetFolder = repo.appendingPathComponent("AppSnap/Assets.xcassets/Bezels")
    let catalogFile = repo.appendingPathComponent("AppSnap/Device/BezelCatalog.swift")

    let (unsortedEntries, errors) = collectEntries(source: source)
    guard errors.isEmpty else {
        print("Import failed, nothing was written:\n")
        for error in errors {
            print("  - \(error)")
        }
        return 1
    }
    let entries = sorted(unsortedEntries)

    let staging = FileManager.default.temporaryDirectory
        .appendingPathComponent("import-bezels-\(UUID().uuidString)")
    defer {
        try? FileManager.default.removeItem(at: staging)
    }
    do {
        let stagedAssets = staging.appendingPathComponent("Bezels")
        try writeAssetFolder(entries, to: stagedAssets)
        let stagedCatalog = staging.appendingPathComponent("BezelCatalog.swift")
        try makeCatalogSource(entries, sourceName: source.lastPathComponent)
            .write(to: stagedCatalog, atomically: true, encoding: .utf8)
        try replace(assetFolder, with: stagedAssets)
        try replace(catalogFile, with: stagedCatalog)
    } catch {
        print("Import failed while writing output: \(error)")
        return 1
    }

    printSummary(entries)
    print("\nImported \(entries.count) bezels.")
    return 0
}

exit(main())
