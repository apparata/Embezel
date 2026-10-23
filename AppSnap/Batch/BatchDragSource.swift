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
/// `draggable` can't. Clicks without a drag are reported instead, so the
/// view can sit on top of a tile and handle selection too. Right clicks and
/// control clicks go through to the SwiftUI view below, for its context
/// menu.
///
/// Files can't be dropped back onto the app: a framed file never matches a
/// device, so it could only ever be rejected. SwiftUI's drop handling
/// doesn't honor the drag's allowed operations, so the app's drop delegate
/// checks `isDragging` too.
struct BatchDragSource: NSViewRepresentable {

    /// True while a drag started here is in progress.
    @MainActor static private(set) var isDragging = false

    /// The files to drag, asked for when a drag starts.
    let files: () -> [PromisedFile]

    /// Size of the box each drag image is fitted into, centered on the
    /// mouse. When nil, the images are fitted into the view's bounds, where
    /// a tile shows its thumbnail.
    var dragImageSize: CGSize?

    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        update(view)
    }

    private func update(_ view: DragSourceView) {
        view.files = files
        view.dragImageSize = dragImageSize
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
    }

    final class DragSourceView: NSView, NSDraggingSource {

        var files: () -> [PromisedFile] = { [] }
        var dragImageSize: CGSize?
        var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
        var onDoubleClick: () -> Void = {}

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
                if mouseDownEvent.clickCount == 2 {
                    onDoubleClick()
                } else {
                    onClick(mouseDownEvent.modifierFlags)
                }
            }
            mouseDownEvent = nil
            isDragging = false
        }

        private func startDrag(with event: NSEvent) {
            let files = files()
            guard !files.isEmpty else {
                return
            }
            let box: CGRect
            if let dragImageSize {
                let mouse = convert(event.locationInWindow, from: nil)
                box = CGRect(
                    x: mouse.x - dragImageSize.width / 2,
                    y: mouse.y - dragImageSize.height / 2,
                    width: dragImageSize.width,
                    height: dragImageSize.height
                )
            } else {
                box = bounds
            }
            let items = files.enumerated().map { index, file in
                let provider = FilePromise(file: file)
                let item = NSDraggingItem(pasteboardWriter: provider)
                // Stack the images slightly; AppKit adds a count badge.
                let offset = CGFloat(min(index, 4)) * 4
                let frame = Self.aspectFit(file.thumbnail?.size, in: box).offsetBy(dx: offset, dy: -offset)
                item.setDraggingFrame(frame, contents: file.thumbnail)
                return item
            }
            BatchDragSource.isDragging = true
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            BatchDragSource.isDragging = false
        }

        /// The largest rectangle with the image's aspect ratio that fits in
        /// the box, centered.
        private static func aspectFit(_ size: CGSize?, in box: CGRect) -> CGRect {
            guard let size, size.width > 0, size.height > 0 else {
                return box
            }
            let scale = min(box.width / size.width, box.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            return CGRect(
                x: box.midX - fitted.width / 2,
                y: box.midY - fitted.height / 2,
                width: fitted.width,
                height: fitted.height
            )
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
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
