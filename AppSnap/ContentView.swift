//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import Constructs
import UniformTypeIdentifiers

struct ContentView: View {

    @State private var model = ContentModel()

    @State private var isDoneBouncing = true

    @State private var isImporterPresented = false

    @State var startDate: Date?

    @State var footerOpacity: CGFloat = 0

    @State var toastModel = ToastModel()
    @State var toastMessage: String = ""

    @State private var window: NSWindow?

    /// Size of the area the composite is fitted into, used to work out how
    /// much of the window is taken up by padding and controls.
    @State private var previewAreaSize: CGSize = .zero

    /// Composite size the window should be resized for, once the preview
    /// area has been laid out.
    @State private var pendingResize: CGSize?

    /// Content size the window should be resized to, for batch mode.
    @State private var pendingContentSize: CGSize?

    /// Progress of a running export.
    @State private var exportProgress: Double?

    /// Title of the export progress overlay.
    @State private var exportTitle = "Exporting Video…"

    @State private var exportTask: Task<Void, Never>?

    @State private var isBackgroundHelpPresented = false

    @State private var isDragOutAlertPresented = false

    /// Set while the mouse is down after a drag on a recording, so a single
    /// drag shows the alert only once.
    @State private var isDraggingVideo = false

    // MARK: - Body

    var body: some View {
        VStack {
            if let batch = model.batch {
                BatchView(batch: batch)
                    .transition(.opacity)
            } else if model.source != nil {
                VStack(spacing: 20) {
                    previewArea
                    controls
                        .opacity(footerOpacity)
                }
                .padding(40)
                .transition(.identity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 72))
                    Text("Drop iPhone screenshots or\n screen recordings here")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowReflection(window: $window))
        .onChange(of: window) {
            deferResize()
        }
        // Open files in this window instead of creating a new one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onChange(of: model.compositeSize) { _, size in
            scheduleResize(toFit: size)
        }
        .onChange(of: model.batch != nil) { _, isBatch in
            if isBatch {
                scheduleResize(toContentSize: Self.batchSize)
            }
        }

        // MARK: - Toast Overlay

        .overlay(alignment: .top) {
            HStack(alignment: .bottom) {
                if toastModel.isShowingToast {
                    Toast(toastMessage)
                        .transition(.move(edge: .top))
                        .padding(.top, 16)
                }
            }
        }

        // MARK: - Export Progress Overlay

        .overlay {
            if let exportProgress {
                exportProgressView(exportProgress)
            }
        }

        // MARK: - Drop Destination

        // A single drop handler: stacked drop destinations don't combine,
        // and recordings can arrive as a file URL or as promised movie data
        // (the Simulator's recording thumbnail, for example).
        .onDrop(of: Self.dropTypes, delegate: FileDropDelegate(types: Self.dropTypes) { providers in
            handleDrop(providers)
        })

        // MARK: - On Open URL

        .onOpenURL { url in
            open([.file(url)])
        }

        // MARK: - File Importer

        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .jpeg, .movie, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                open(urls.map { .file($0) }, isSecurityScoped: true)
            case .failure(let error):
                dump(error)
            }
        }

        // MARK: - Toolbar

        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    isImporterPresented = true
                } label: {
                    Image(systemName: "folder")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    if model.batch != nil {
                        withAnimation {
                            model.clear()
                        }
                        return
                    }
                    Task {
                        await model.freezeVideoFrame()
                        startDate = Date()
                        withAnimation(.smooth) {
                            footerOpacity = 0
                        }
                        try? await Task.sleep(for: .seconds(0.5))
                        withAnimation {
                            model.clear()
                            startDate = nil
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    if let batch = model.batch {
                        exportBatch(batch)
                    } else if let selection = model.selection {
                        if model.isVideo {
                            exportVideo(name: selection.fileName)
                        } else if let image = model.compositedImage {
                            exportImage(image, name: selection.fileName)
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(exportProgress != nil || (model.isVideo && model.videoComposition == nil))
            }
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        Group {
            if let startDate {
                TimelineView(.animation) { context in
                    // Derive time from the timeline's date. The content has
                    // to depend on it, or SwiftUI doesn't redraw on each tick.
                    let t = context.date.timeIntervalSince(startDate) * 2
                    deviceView
                        .scaleEffect(isDoneBouncing ? 1.0 : 0.9)
                        .visualEffect { content, proxy in
                            content
                                .colorEffect(removeEffect(
                                    t: t,
                                    size: proxy.size
                                ))
                        }
                }
            } else {
                deviceView
                    .scaleEffect(isDoneBouncing ? 1.0 : 0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            previewAreaSize = size
            deferResize()
        }
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            if let selection = model.selection {
                BezelControls(
                    choices: model.choices,
                    selection: selection,
                    onSelectModelColor: { model.select($0) },
                    onSelectPose: { model.select($0) },
                    onRotate: { model.toggleRotation() }
                )

                if model.isVideo {
                    videoBackgroundControls
                }
            }
        }
    }

    /// Transparent exports are HEVC with alpha, which not every player
    /// supports, so a solid background is offered too.
    private var videoBackgroundControls: some View {
        HStack {
            Picker("Background", selection: Binding(
                get: { model.videoBackground.isTransparent },
                set: { isTransparent in
                    withAnimation(.smooth(duration: 0.25)) {
                        model.setVideoBackground(isTransparent ? .transparent : .color(model.videoBackgroundColor))
                    }
                }
            )) {
                Text("Transparent").tag(true)
                Text("Color").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Background of the exported video")

            if !model.videoBackground.isTransparent {
                ColorPicker("Background Color", selection: Binding(
                    get: { model.videoBackgroundColor },
                    set: { model.setVideoBackground(.color($0)) }
                ), supportsOpacity: false)
                .labelsHidden()
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            HelpLink {
                isBackgroundHelpPresented = true
            }
            .controlSize(.small)
            .popover(isPresented: $isBackgroundHelpPresented, arrowEdge: .bottom) {
                backgroundHelp
            }
        }
    }

    private var backgroundHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transparent")
                    .font(.headline)
                Text("""
                    Only the device is visible; everything around it is see-through. \
                    Exported as an HEVC video with alpha (.mov), which works in QuickTime, \
                    Safari, Keynote and Final Cut Pro, but not in every app or browser. \
                    Elsewhere the background may show up as black.
                    """)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Color")
                    .font(.headline)
                Text("""
                    The device is placed on a solid color of your choice. \
                    Exported as a regular HEVC video (.mp4) that plays almost anywhere.
                    """)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300)
        .padding()
    }

    // MARK: - Device View

    @ViewBuilder var deviceView: some View {
        if let compositedImage = model.compositedImage, let selection = model.selection {
            Image(nsImage: compositedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .onDrag {
                    // Save the image temporarily to a file URL
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(selection.fileName).png")

                    if let tiffData = compositedImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: tempURL)
                    }

                    guard let provider = NSItemProvider(contentsOf: tempURL) else {
                        fatalError()
                    }
                    return provider.applying { provider in
                        provider.suggestedName = selection.fileName
                    }
                }
        } else if model.isVideo, model.videoComposition != nil, let size = model.compositeSize {
            PlayerView(player: model.player)
                .aspectRatio(size, contentMode: .fit)
                .contentShape(Rectangle())
                .onTapGesture {
                    if model.player.timeControlStatus == .paused {
                        model.player.play()
                    } else {
                        model.player.pause()
                    }
                }
                // A recording would have to be exported before it could be
                // dropped somewhere, which blocks, so offer to export instead.
                .gesture(DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        if !isDraggingVideo {
                            isDraggingVideo = true
                            isDragOutAlertPresented = true
                        }
                    }
                    .onEnded { _ in
                        isDraggingVideo = false
                    }
                )
                .help("Click to play or pause")
                .alert("Videos Can’t Be Dragged Out", isPresented: $isDragOutAlertPresented) {
                    Button("Export…") {
                        if let selection = model.selection {
                            exportVideo(name: selection.fileName)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("A framed video has to be encoded to a file first, which can take a while. Do you want to export it?")
                }
        }
    }

    // MARK: - Load

    /// Runs a load action and shows a toast if it fails.
    @discardableResult
    private func load(_ action: () throws -> Void) -> Bool {
        do {
            try action()
        } catch {
            showError(error)
            return false
        }
        didLoad()
        return true
    }

    /// Runs a load action that may take a while, such as opening a
    /// recording, and shows a toast if it fails.
    private func loadAsync(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                showError(error)
                return
            }
            didLoad()
        }
    }

    // MARK: - Drop

    private static let dropTypes: [UTType] = [.fileURL, .movie, .image]

    /// Accepts dropped files, except ones dragged out of the batch grid:
    /// those are framed already and could never be opened.
    private struct FileDropDelegate: DropDelegate {
        let types: [UTType]
        let perform: ([NSItemProvider]) -> Bool

        func validateDrop(info: DropInfo) -> Bool {
            !BatchDragSource.isDragging && info.hasItemsConforming(to: types)
        }

        func performDrop(info: DropInfo) -> Bool {
            guard !BatchDragSource.isDragging else {
                return false
            }
            return perform(info.itemProviders(for: types))
        }
    }

    /// Something dropped or opened.
    enum OpenedItem {
        case file(URL)
        case image(NSImage)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else {
            return false
        }
        Task { @MainActor in
            var items: [OpenedItem] = []
            for provider in providers {
                if let item = await resolve(provider) {
                    items.append(item)
                }
            }
            if items.isEmpty {
                showToast(AppError.unsupportedFile.message)
            } else {
                open(items)
            }
        }
        return true
    }

    /// Turns a dropped item into a file URL or an image. Recordings can
    /// arrive as a file URL or as promised movie data (the Simulator's
    /// recording thumbnail, for example).
    private func resolve(_ provider: NSItemProvider) async -> OpenedItem? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadTransferable(type: URL.self) { result in
                    switch result {
                    case .success(let url):
                        continuation.resume(returning: .file(url))
                    case .failure(let error):
                        print("Could not load dropped URL: \(error)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            // The file only exists until the handler returns, so it is
            // copied somewhere that lasts while the recording is open.
            return await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let url else {
                        print("Could not load dropped movie: \(String(describing: error))")
                        continuation.resume(returning: nil)
                        return
                    }
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    let destination = directory.appendingPathComponent(url.lastPathComponent)
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: url, to: destination)
                        continuation.resume(returning: .file(destination))
                    } catch {
                        print("Could not copy dropped movie: \(error)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    continuation.resume(returning: (image as? NSImage).map { .image($0) })
                }
            }
        }

        return nil
    }

    /// Opens dropped, opened or imported items. More than one supported
    /// file, or any folder, makes a batch; so does anything opened while a
    /// batch is showing. Otherwise the single file opens as before.
    private func open(_ items: [OpenedItem], isSecurityScoped: Bool = false) {
        let urls = items.compactMap { item -> URL? in
            if case .file(let url) = item {
                return url
            }
            return nil
        }
        let images = items.compactMap { item -> NSImage? in
            if case .image(let image) = item {
                return image
            }
            return nil
        }

        // Folders from the file importer must be accessed before they can
        // be listed.
        let scopedURLs = isSecurityScoped ? urls.filter { $0.startAccessingSecurityScopedResource() } : []
        let (files, containsFolder) = BatchPlanning.expand(urls)
        let supportedCount = files.filter { MediaKind(url: $0) != nil }.count + images.count

        if model.batch == nil, !containsFolder, files.count + images.count == 1 {
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            if let url = files.first {
                loadAsync { try await model.load(from: url, isSecurityScoped: isSecurityScoped) }
            } else if let image = images.first {
                load { try model.loadScreenshot(image) }
            }
            return
        }

        guard supportedCount > 0 || model.batch != nil || files.count + images.count > 1 else {
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            showToast(AppError.unsupportedFile.message)
            return
        }

        let inputs = files.map { BatchInput(url: $0) } + images.compactMap { image in
            image.cgImage(forProposedRect: nil, context: nil, hints: nil).map { BatchInput(image: $0) }
        }
        withAnimation(.smooth) {
            model.addToBatch(inputs)
        }
        model.batch?.adoptSecurityScopedURLs(scopedURLs)
    }

    private func showError(_ error: Error) {
        if let error = error as? AppError {
            showToast(error.message)
        } else {
            showToast("Unexpected error")
        }
    }

    private func didLoad() {
        bounce()
        withAnimation(.smooth) {
            footerOpacity = 1
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        toastModel.showToast()
    }

    // MARK: - Export Image

    func exportImage(_ image: NSImage, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(name).png"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: url)
                }
            }
        }
    }

    // MARK: - Export Video

    func exportVideo(name: String) {
        let type = VideoExporter.contentType(for: model.videoBackground)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "\(name).\(type.preferredFilenameExtension ?? "mov")"
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            exportTitle = "Exporting Video…"
            exportProgress = 0
            exportTask = Task {
                do {
                    try await model.exportVideo(to: url) { progress in
                        exportProgress = progress
                    }
                } catch is CancellationError {
                    // Cancelled by the user.
                } catch {
                    showError(error)
                }
                exportProgress = nil
                exportTask = nil
            }
        }
    }

    // MARK: - Export Batch

    /// Exports the selected items, or all of them, to a folder.
    func exportBatch(_ batch: BatchModel) {
        let ids = batch.selectedIDs.isEmpty ? Set(batch.items.map(\.id)) : batch.selectedIDs
        let files = batch.dragFiles(for: ids)
        let skipped = ids.count - files.count
        guard !files.isEmpty else {
            showToast("Nothing to export yet")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = files.count == 1 ? "Choose a folder for the framed file." : "Choose a folder for the \(files.count) framed files."
        panel.directoryURL = batch.items.compactMap(\.originalURL).first?.deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let folder = panel.url else {
                return
            }
            exportTitle = "Exporting…"
            exportProgress = 0
            exportTask = Task {
                do {
                    let summary = try await BatchExporter.export(files, skipped: skipped, to: folder) { done, total in
                        exportTitle = "Exporting \(min(done + 1, total)) of \(total)…"
                        exportProgress = total > 0 ? Double(done) / Double(total) : 1
                    }
                    showToast(summary.message)
                } catch is CancellationError {
                    showToast("Export cancelled")
                } catch {
                    showError(error)
                }
                exportProgress = nil
                exportTask = nil
            }
        }
    }

    private func exportProgressView(_ progress: Double) -> some View {
        VStack(spacing: 12) {
            Text(exportTitle)
                .font(.headline)
            ProgressView(value: progress)
                .frame(width: 200)
            Button("Cancel") {
                exportTask?.cancel()
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Window Resizing

    /// Smallest size of the window's content area. Narrower than 400 pt and
    /// the toolbar buttons overflow into a menu.
    static let minimumSize = CGSize(width: 400, height: 360)

    /// Content size of the window when a batch opens.
    static let batchSize = CGSize(width: 820, height: 700)

    private func scheduleResize(toContentSize size: CGSize) {
        pendingResize = nil
        pendingContentSize = size
        deferResize()
    }

    private func scheduleResize(toFit size: CGSize?) {
        pendingResize = size
        deferResize()
    }

    /// Resizes the window later, outside of SwiftUI's update and layout
    /// passes. Only the default run loop mode is used, so a click on a
    /// control (which runs a mouse tracking loop) has finished first.
    /// Resizing the window while SwiftUI renders makes NSHostingView lay
    /// out reentrantly, which it skips.
    private func deferResize() {
        guard pendingResize != nil || pendingContentSize != nil else {
            return
        }
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                resizeWindowIfNeeded()
            }
        }
    }

    /// Resizes the window so the composite fills the preview area, keeping
    /// the window's content area and center. Padding and controls keep
    /// their size, so they are left out of the aspect ratio.
    private func resizeWindowIfNeeded() {
        if let window, let size = pendingContentSize {
            pendingContentSize = nil
            setWindowContentSize(size, of: window)
            return
        }
        guard let window, let imageSize = pendingResize, imageSize.width > 0, imageSize.height > 0,
              previewAreaSize.width > 0, previewAreaSize.height > 0 else {
            return
        }
        pendingResize = nil

        // The layout rect excludes the title bar and toolbar.
        let contentSize = window.contentLayoutRect.size
        let chrome = CGSize(
            width: window.frame.width - contentSize.width,
            height: window.frame.height - contentSize.height
        )
        let overhead = CGSize(
            width: contentSize.width - previewAreaSize.width,
            height: contentSize.height - previewAreaSize.height
        )
        let aspect = imageSize.width / imageSize.height

        // Skip if the preview area already has the right aspect.
        if abs(previewAreaSize.width / previewAreaSize.height - aspect) / aspect < 0.02 {
            return
        }

        func width(forHeight height: CGFloat) -> CGFloat {
            aspect * (height - overhead.height) + overhead.width
        }
        func height(forWidth width: CGFloat) -> CGFloat {
            (width - overhead.width) / aspect + overhead.height
        }

        // Solve width(forHeight: h) * h = area for h.
        let area = contentSize.width * contentSize.height
        let b = overhead.width - aspect * overhead.height
        let solvedHeight = (-b + (b * b + 4 * aspect * area).squareRoot()) / (2 * aspect)
        var size = CGSize(width: width(forHeight: solvedHeight), height: solvedHeight)

        // Grow to the minimum size, keeping the preview aspect.
        if size.width < Self.minimumSize.width {
            size = CGSize(width: Self.minimumSize.width, height: height(forWidth: Self.minimumSize.width))
        }
        if size.height < Self.minimumSize.height {
            size = CGSize(width: width(forHeight: Self.minimumSize.height), height: Self.minimumSize.height)
        }

        // Shrink to fit the screen, keeping the preview aspect.
        if let visible = window.screen?.visibleFrame {
            let maxSize = CGSize(width: visible.width - chrome.width, height: visible.height - chrome.height)
            if size.width > maxSize.width {
                size = CGSize(width: maxSize.width, height: height(forWidth: maxSize.width))
            }
            if size.height > maxSize.height {
                size = CGSize(width: width(forHeight: maxSize.height), height: maxSize.height)
            }
        }

        setWindowContentSize(size, of: window)
    }

    /// Animates the window to a content size, keeping its center and
    /// staying on screen.
    private func setWindowContentSize(_ size: CGSize, of window: NSWindow) {
        let contentSize = window.contentLayoutRect.size
        let chrome = CGSize(
            width: window.frame.width - contentSize.width,
            height: window.frame.height - contentSize.height
        )
        var size = size
        if let visible = window.screen?.visibleFrame {
            size.width = min(size.width, visible.width - chrome.width)
            size.height = min(size.height, visible.height - chrome.height)
        }
        var frame = CGRect(
            x: 0,
            y: 0,
            width: (size.width + chrome.width).rounded(),
            height: (size.height + chrome.height).rounded()
        )
        frame.origin = CGPoint(x: window.frame.midX - frame.width / 2, y: window.frame.midY - frame.height / 2)
        if let visible = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        // Animate through the animator proxy; setFrame(_:display:animate:)
        // runs a blocking animation loop that lays out SwiftUI reentrantly.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Bounce

    private func bounce() {
        isDoneBouncing = false
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            isDoneBouncing = true
        }
    }

    // MARK: - Remove Effect

    nonisolated
    private func removeEffect(t: Double, size: CGSize) -> Shader {
        ShaderLibrary.removeEffect(
            .float(t),
            .float2(size)
        )
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
