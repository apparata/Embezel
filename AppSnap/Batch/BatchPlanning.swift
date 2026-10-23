//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Input

/// Something to add to a batch: a file, or an image that was dropped
/// without a file behind it.
struct BatchInput {

    enum Source {
        case file(URL)
        case image(CGImage)
    }

    let source: Source

    /// Name without extension, used for output file names.
    let name: String

    init(url: URL) {
        source = .file(url)
        name = url.deletingPathExtension().lastPathComponent
    }

    init(image: CGImage, name: String = "Screenshot") {
        source = .image(image)
        self.name = name
    }
}

enum MediaKind {
    case image
    case video

    init?(url: URL) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else {
            return nil
        }
        if type.conforms(to: .movie) {
            self = .video
        } else if type.conforms(to: .image) {
            self = .image
        } else {
            return nil
        }
    }
}

// MARK: - Planning

/// The parts of batch processing that don't depend on UI or rendering.
enum BatchPlanning {

    // MARK: Files

    /// Replaces folders with the files directly inside them, skipping hidden
    /// files and subfolders, sorted by name like Finder does.
    static func expand(_ urls: [URL]) -> (files: [URL], containsFolder: Bool) {
        var files: [URL] = []
        var containsFolder = false
        for url in urls {
            guard isDirectory(url) else {
                files.append(url)
                continue
            }
            containsFolder = true
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            files += contents
                .filter { !isDirectory($0) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        return (files, containsFolder)
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    // MARK: Groups

    /// Items with the same candidate models share a group: same-size
    /// screenshots in either orientation, and recordings that match by
    /// aspect ratio.
    static func groupKey(for candidates: [Bezel]) -> String {
        candidates.map(\.model).uniqued().joined(separator: "|")
    }

    /// Poses the group's pose control offers: those of items that fit more
    /// than one pose with the chosen model and color (today only the Duo's
    /// outer display in portrait: Closed or Open).
    static func poseOptions(for itemCandidates: [[Bezel]], modelColor: ModelColor) -> [Pose] {
        itemCandidates
            .map { BezelChoices(candidates: $0).poses(for: modelColor) }
            .filter { $0.count > 1 }
            .flatMap { $0 }
            .uniqued()
    }

    // MARK: File Names

    /// For example "IMG_0042 - iPhone 17 Pro - Deep Blue - Portrait".
    static func outputName(original: String, selection: Selection) -> String {
        "\(original) - \(selection.fileName)"
    }

    /// Adds " 2", " 3", … until the name isn't taken. Names are compared
    /// case-insensitively, as on the default macOS file system.
    static func uniqueFileName(_ name: String, extension fileExtension: String, taken: inout Set<String>) -> String {
        var candidate = "\(name).\(fileExtension)"
        var number = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(name) \(number).\(fileExtension)"
            number += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }

    /// File names already in a folder, lowercased, for `uniqueFileName`.
    static func existingFileNames(in directory: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.map { $0.lowercased() })
    }
}
