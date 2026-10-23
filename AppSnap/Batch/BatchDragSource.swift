//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Promised File

/// A file handed over by dragging. The receiver gets it through a file
/// promise, which is written after the drop; if the file already exists,
/// its URL is offered too, for apps that don't accept promises.
struct PromisedFile {
    let fileName: String
    let fileType: UTType
    let existingFile: URL?
    let thumbnail: NSImage?

    /// Writes the file to the promised URL. Called after the drop, off the
    /// main thread.
    let write: @Sendable (URL) async throws -> Void

    /// A file that has already been written, copied on drop.
    static func copy(of url: URL, named fileName: String, thumbnail: NSImage?) -> PromisedFile {
        PromisedFile(
            fileName: fileName,
            fileType: UTType(filenameExtension: url.pathExtension) ?? .data,
            existingFile: url,
            thumbnail: thumbnail,
            write: { destination in
                try FileManager.default.copyItem(at: url, to: destination)
            }
        )
    }
}

// MARK: - Drag Source

/// Starts a drag with any number of files, which SwiftUI's `onDrag` and
/// `draggable` can't. A click without a drag is reported instead, so the
/// view can sit on top of a tile and handle selection too. Right clicks and
/// control clicks go through to the SwiftUI view below, for its context
/// menu.
struct BatchDragSource: NSViewRepresentable {

    /// The files to drag, asked for when a drag starts.
    let files: () -> [PromisedFile]
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.files = files
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.files = files
        view.onClick = onClick
    }

    final class DragSourceView: NSView, NSDraggingSource {

        var files: () -> [PromisedFile] = { [] }
        var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }

        private var mouseDownEvent: NSEvent?
        private var isDragging = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent {
                let isContextClick = event.type == .rightMouseDown
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
                if isContextClick {
                    return nil
                }
            }
            return super.hitTest(point)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !isDragging, let mouseDownEvent else {
                return
            }
            let start = mouseDownEvent.locationInWindow
            let current = event.locationInWindow
            guard hypot(current.x - start.x, current.y - start.y) > 4 else {
                return
            }
            isDragging = true
            startDrag(with: mouseDownEvent)
        }

        override func mouseUp(with event: NSEvent) {
            if !isDragging, let mouseDownEvent {
                onClick(mouseDownEvent.modifierFlags)
            }
            mouseDownEvent = nil
            isDragging = false
        }

        private func startDrag(with event: NSEvent) {
            let files = files()
            guard !files.isEmpty else {
                return
            }
            let items = files.enumerated().map { index, file in
                let provider = FilePromise(file: file)
                let item = NSDraggingItem(pasteboardWriter: provider)
                // Stack the images slightly; AppKit adds a count badge.
                let offset = CGFloat(min(index, 4)) * 4
                item.setDraggingFrame(bounds.offsetBy(dx: offset, dy: -offset), contents: file.thumbnail)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }
    }
}

// MARK: - File Promise

/// A file promise that also offers an existing file's URL. Its delegate is
/// held strongly, because `NSFilePromiseProvider` only keeps a weak one and
/// the drag outlives the view that started it.
private final class FilePromise: NSFilePromiseProvider {

    private let writer: PromiseWriter
    private let existingFile: URL?

    init(file: PromisedFile) {
        writer = PromiseWriter(file: file)
        existingFile = file.existingFile
        super.init()
        fileType = file.fileType.identifier
        delegate = writer
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if existingFile != nil {
            types.append(.fileURL)
        }
        return types
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL, let existingFile {
            return (existingFile as NSURL).pasteboardPropertyList(forType: type)
        }
        return super.pasteboardPropertyList(forType: type)
    }
}

private final class PromiseWriter: NSObject, NSFilePromiseProviderDelegate {

    /// Writes promised files one at a time, so several encoded recordings
    /// don't compete with each other.
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Embezel file promises"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private let file: PromisedFile

    init(file: PromisedFile) {
        self.file = file
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        file.fileName
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // The operation queue runs this; waiting here keeps the next
        // promise from starting before this one is written.
        let semaphore = DispatchSemaphore(value: 0)
        let write = file.write
        Task.detached(priority: .userInitiated) {
            do {
                try await write(url)
                completionHandler(nil)
            } catch {
                print("Could not write promised file \(url.lastPathComponent): \(error)")
                completionHandler(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.queue
    }
}
