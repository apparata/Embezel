//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Several screenshots framed at once.
///
/// Items are grouped by the models that fit them. Each group has one model
/// and color choice, and an item can have its own choice instead, which it
/// keeps when the group's choice changes. Every ready item is rendered to a
/// PNG in a temporary folder, so it can be dragged out as a file; only a
/// thumbnail is kept in memory.
@MainActor @Observable final class BatchModel {

    enum Status: Equatable {
        case loading
        case ready
        case unsupported(String)
        case failed(String)
    }

    /// An item's own model, color and pose, instead of its group's.
    struct Override: Hashable {
        let modelColor: ModelColor
        let pose: Pose?
    }

    struct Item: Identifiable {
        let id = UUID()
        let name: String
        let source: BatchInput.Source
        var kind: MediaKind = .image
        var candidates: [Bezel] = []
        var groupID: String?
        var override: Override?
        var isRotated180 = false
        var status: Status = .loading
        var isRendering = false
        var thumbnail: NSImage?

        /// The selection the rendered file was made with.
        var selection: Selection?
        var renderedURL: URL?

        var originalURL: URL? {
            if case .file(let url) = source {
                return url
            }
            return nil
        }

        var isReady: Bool {
            status == .ready && renderedURL != nil && !isRendering
        }

        /// Output file name without extension.
        var outputName: String? {
            selection.map { BatchPlanning.outputName(original: name, selection: $0) }
        }
    }

    struct Group: Identifiable {
        let id: String
        var modelColor: ModelColor
        var pose: Pose?
    }

    private(set) var items: [Item] = []
    private(set) var groups: [Group] = []
    var selectedIDs: Set<Item.ID> = []

    /// Holds one subfolder per item with its rendered file.
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var renderTasks: [Item.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private let limiter = RenderLimiter(limit: 4)
    @ObservationIgnored private var securityScopedURLs: [URL] = []

    /// Prefix of the temporary folders batches render into.
    private nonisolated static let directoryPrefix = "Embezel-Batch-"

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.directoryPrefix)\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Adding and Removing

    func add(_ inputs: [BatchInput]) {
        for input in inputs {
            let item = Item(name: input.name, source: input.source)
            items.append(item)
            load(item.id)
        }
    }

    /// Keeps access to security-scoped URLs (from the file importer) until
    /// the batch is cleared. Access must already have been started.
    func adoptSecurityScopedURLs(_ urls: [URL]) {
        securityScopedURLs += urls
    }

    func remove(_ ids: Set<Item.ID>) {
        for id in ids {
            renderTasks[id]?.cancel()
            renderTasks[id] = nil
            try? FileManager.default.removeItem(at: itemDirectory(id))
        }
        items.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        let usedGroups = Set(items.compactMap(\.groupID))
        groups.removeAll { !usedGroups.contains($0.id) }
    }

    func clear() {
        renderTasks.values.forEach { $0.cancel() }
        renderTasks = [:]
        items = []
        groups = []
        selectedIDs = []
        try? FileManager.default.removeItem(at: directory)
        securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedURLs = []
    }

    /// Removes all batch folders, including ones left behind by a crash.
    /// Called at launch and quit, when no batch is open.
    nonisolated static func removeTemporaryFolders() {
        let temporary = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temporary.path)) ?? []
        for name in names where name.hasPrefix(directoryPrefix) {
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent(name))
        }
    }

    // MARK: - Queries

    func item(_ id: Item.ID) -> Item? {
        items.first { $0.id == id }
    }

    func items(in group: Group) -> [Item] {
        items.filter { $0.groupID == group.id }
    }

    var unsupportedItems: [Item] {
        items.filter { $0.groupID == nil && $0.status != .loading }
    }

    /// Items that haven't been matched to a group yet.
    var loadingItems: [Item] {
        items.filter { $0.groupID == nil && $0.status == .loading }
    }

    /// All bezels that fit some item in the group, for its picker.
    func choices(for group: Group) -> BezelChoices {
        var seen: Set<String> = []
        let candidates = items(in: group)
            .flatMap(\.candidates)
            .filter { seen.insert($0.imageName).inserted }
        return BezelChoices(candidates: candidates)
    }

    func poseOptions(for group: Group) -> [Pose] {
        BatchPlanning.poseOptions(for: items(in: group).map(\.candidates), modelColor: group.modelColor)
    }

    /// The group's models, e.g. "iPhone 17 Pro · iPhone 17 · iPhone 16 Pro".
    func title(for group: Group) -> String {
        choices(for: group).models.joined(separator: " · ")
    }

    /// Ready items to drag or export: the given ones, in batch order.
    func readyItems(_ ids: Set<Item.ID>) -> [Item] {
        items.filter { ids.contains($0.id) && $0.isReady }
    }

    var readyItems: [Item] {
        items.filter(\.isReady)
    }

    /// Files for dragging out the given ready items. Names that would
    /// collide within the drag get a " 2" suffix.
    func dragFiles(for ids: Set<Item.ID>) -> [PromisedFile] {
        var taken: Set<String> = []
        return readyItems(ids).compactMap { item in
            guard let url = item.renderedURL, let name = item.outputName else {
                return nil
            }
            let fileName = BatchPlanning.uniqueFileName(name, extension: url.pathExtension, taken: &taken)
            return PromisedFile.copy(of: url, named: fileName, thumbnail: item.thumbnail)
        }
    }

    /// The bezel an item is framed with: its own choice, or else its
    /// group's, plus its own rotation.
    func effectiveSelection(for item: Item) -> Selection? {
        let choices = BezelChoices(candidates: item.candidates)
        var bezel: Bezel?
        if let override = item.override {
            bezel = choices.bezel(for: override.modelColor, preferring: override.pose)
        } else if let group = groups.first(where: { $0.id == item.groupID }) {
            bezel = choices.bezel(for: group.modelColor, preferring: group.pose)
        }
        return (bezel ?? item.candidates.first).map { Selection(bezel: $0, isRotated180: item.isRotated180) }
    }

    // MARK: - Choices

    func setModelColor(_ modelColor: ModelColor, for groupID: Group.ID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        groups[index].modelColor = modelColor
        renderGroup(groupID)
    }

    func setPose(_ pose: Pose, for groupID: Group.ID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        groups[index].pose = pose
        renderGroup(groupID)
    }

    /// Gives the item its own model and color, keeping its pose if it fits.
    func setModelColor(_ modelColor: ModelColor, forItem id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        let pose = items[index].selection?.bezel.pose
        items[index].override = Override(modelColor: modelColor, pose: pose)
        render(id)
    }

    func setPose(_ pose: Pose, forItem id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let selection = effectiveSelection(for: items[index]) else {
            return
        }
        let modelColor = ModelColor(model: selection.bezel.model, color: selection.bezel.color)
        items[index].override = Override(modelColor: modelColor, pose: pose)
        render(id)
    }

    /// Lets the item follow its group's choice again.
    func useGroupSetting(_ ids: Set<Item.ID>) {
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].override != nil else {
                continue
            }
            items[index].override = nil
            render(id)
        }
    }

    /// Rotates landscape items 180°; other items are left alone.
    func toggleRotation(_ ids: Set<Item.ID>) {
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }),
                  items[index].selection?.bezel.pose.isLandscape == true else {
                continue
            }
            items[index].isRotated180.toggle()
            render(id)
        }
    }

    // MARK: - Loading

    private func load(_ id: Item.ID) {
        guard let item = item(id) else {
            return
        }
        let source = item.source
        renderTasks[id] = Task {
            let probe = await Task.detached(priority: .userInitiated) {
                Self.probe(source)
            }.value
            guard !Task.isCancelled else {
                return
            }
            apply(probe, to: id)
        }
    }

    private struct Probe {
        var kind: MediaKind?
        var size: CGSize?
        var rotation: RotationDetector.Guess = .unknown
    }

    /// Reads what's needed to match bezels. Only landscape screenshots are
    /// decoded fully, for rotation detection.
    private nonisolated static func probe(_ source: BatchInput.Source) -> Probe {
        switch source {
        case .image(let image):
            let size = CGSize(width: image.width, height: image.height)
            let rotation = size.width > size.height ? RotationDetector.detect(image) : .unknown
            return Probe(kind: .image, size: size, rotation: rotation)
        case .file(let url):
            guard let kind = MediaKind(url: url) else {
                return Probe()
            }
            guard kind == .image else {
                return Probe(kind: kind)
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                return Probe(kind: kind)
            }
            var probe = Probe(kind: kind, size: CGSize(width: width, height: height))
            if width > height, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                probe.rotation = RotationDetector.detect(image)
            }
            return probe
        }
    }

    private func apply(_ probe: Probe, to id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard let kind = probe.kind else {
            items[index].status = .unsupported(AppError.unsupportedFile.message)
            return
        }
        items[index].kind = kind
        guard kind == .image else {
            items[index].status = .unsupported("Recordings aren’t supported in batches yet")
            return
        }
        guard let size = probe.size else {
            items[index].status = .failed(AppError.unsupportedFile.message)
            return
        }
        let candidates = BezelMatching.bezels(for: size, allowScaling: false)
        guard let first = candidates.first else {
            let message = BezelMatching.droppedDevice(for: size).map { AppError.droppedDevice($0).message }
                ?? AppError.unsupportedScreenshotSize.message
            items[index].status = .unsupported(message)
            return
        }

        let groupID = BatchPlanning.groupKey(for: candidates)
        items[index].candidates = candidates
        items[index].groupID = groupID
        if !groups.contains(where: { $0.id == groupID }) {
            groups.append(Group(id: groupID, modelColor: ModelColor(model: first.model, color: first.color)))
            sortGroups()
        }
        items[index].isRotated180 = first.pose.isLandscape && probe.rotation == .rotated180
        render(id)
    }

    /// Orders groups by where their first item is in the batch. Items are
    /// probed in parallel, so groups are created in no particular order.
    private func sortGroups() {
        let firstIndex = Dictionary(
            items.enumerated().compactMap { index, item in item.groupID.map { ($0, index) } },
            uniquingKeysWith: min
        )
        groups.sort { (firstIndex[$0.id] ?? .max) < (firstIndex[$1.id] ?? .max) }
    }

    // MARK: - Rendering

    private func renderGroup(_ groupID: Group.ID) {
        for item in items where item.groupID == groupID && item.override == nil {
            render(item.id)
        }
    }

    /// Renders the item with its current choice, replacing any render in
    /// progress for it. The previous thumbnail stays until the new one is
    /// ready.
    private func render(_ id: Item.ID) {
        renderTasks[id]?.cancel()
        guard let index = items.firstIndex(where: { $0.id == id }),
              let selection = effectiveSelection(for: items[index]) else {
            return
        }
        items[index].isRendering = true
        let source = items[index].source
        let fileName = BatchPlanning.outputName(original: items[index].name, selection: selection) + ".png"
        let folder = itemDirectory(id)
        let limiter = limiter

        renderTasks[id] = Task {
            await limiter.acquire()
            defer {
                Task {
                    await limiter.release()
                }
            }
            guard !Task.isCancelled,
                  let assets = await BezelAssets.shared.loadAssets(for: selection.bezel),
                  !Task.isCancelled else {
                return
            }
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try BatchImageRenderer.render(
                        source: source,
                        selection: selection,
                        bezelImage: assets.image,
                        screenMask: assets.mask,
                        folder: folder,
                        fileName: fileName
                    )
                }
            }.value
            guard !Task.isCancelled else {
                return
            }
            finishRender(id, selection: selection, result: result)
        }
    }

    private func finishRender(_ id: Item.ID, selection: Selection, result: Result<BatchImageRenderer.Output, Error>) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].isRendering = false
        switch result {
        case .success(let output):
            if let old = items[index].renderedURL, old != output.url {
                try? FileManager.default.removeItem(at: old)
            }
            items[index].renderedURL = output.url
            items[index].selection = selection
            items[index].thumbnail = NSImage(
                cgImage: output.thumbnail,
                size: NSSize(width: output.thumbnail.width, height: output.thumbnail.height)
            )
            items[index].status = .ready
        case .failure(let error):
            print("Could not render \(items[index].name): \(error)")
            items[index].status = .failed("Could not frame this image")
        }
    }

    private func itemDirectory(_ id: Item.ID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }
}

// MARK: - Rendering

/// Renders one batch image to a PNG file and a thumbnail. Runs off the main
/// actor.
enum BatchImageRenderer {

    struct Output {
        let url: URL
        let thumbnail: CGImage
    }

    enum RenderError: Error {
        case decodingFailed
        case renderingFailed
        case writingFailed
    }

    /// Longest side of a thumbnail, in pixels.
    static let thumbnailSize = 480

    static func render(
        source: BatchInput.Source,
        selection: Selection,
        bezelImage: CGImage,
        screenMask: CGImage,
        folder: URL,
        fileName: String
    ) throws -> Output {
        let screenshot: CGImage
        switch source {
        case .image(let image):
            screenshot = image
        case .file(let url):
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw RenderError.decodingFailed
            }
            screenshot = image
        }

        guard let framed = BezelRenderer.render(
            screenshot: screenshot,
            bezelImage: bezelImage,
            screenMask: screenMask,
            selection: selection
        ) else {
            throw RenderError.renderingFailed
        }

        // Write to a temporary name first, so a file that is being dragged
        // is never seen half written.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        let partial = folder.appendingPathComponent(".\(UUID().uuidString).png")
        try writePNG(framed, to: partial)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: url)
        }

        return Output(url: url, thumbnail: thumbnail(of: framed) ?? framed)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.writingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RenderError.writingFailed
        }
    }

    private static func thumbnail(of image: CGImage) -> CGImage? {
        let scale = min(1, Double(thumbnailSize) / Double(max(image.width, image.height)))
        let width = max(Int((Double(image.width) * scale).rounded()), 1)
        let height = max(Int((Double(image.height) * scale).rounded()), 1)
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

// MARK: - Render Limiter

/// Lets at most `limit` renders run at the same time.
actor RenderLimiter {

    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = limit
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
