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

    /// Progress of a running recording export.
    @State private var exportProgress: Double?

    @State private var exportTask: Task<Void, Never>?

    @State private var isBackgroundHelpPresented = false

    // MARK: - Body

    var body: some View {
        VStack {
            if model.source != nil {
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
                    Text("Drop iPhone screenshot or\n screen recording here")
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
        .onDrop(of: [.fileURL, .movie, .image], isTargeted: nil) { providers in
            guard let provider = providers.first else {
                return false
            }
            return handleDrop(provider)
        }

        // MARK: - On Open URL

        .onOpenURL { url in
            loadAsync { try await model.load(from: url) }
        }

        // MARK: - File Importer

        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .jpeg, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadAsync { try await model.load(from: url, isSecurityScoped: true) }
                }
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
                    if let selection = model.selection {
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
            if let selection = model.selection, let selected = model.selectedModelColor {
                Picker(selection.bezel.model, selection: Binding(
                    get: { selected },
                    set: { model.select($0) }
                )) {
                    ForEach(model.models, id: \.self) { deviceModel in
                        Section(deviceModel) {
                            ForEach(model.colors(for: deviceModel), id: \.self) { color in
                                Text(color)
                                    .tag(ModelColor(model: deviceModel, color: color))
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260)

                HStack {
                    if model.poses.count > 1 {
                        Picker("Pose", selection: Binding(
                            get: { selection.bezel.pose },
                            set: { model.select($0) }
                        )) {
                            ForEach(model.poses, id: \.self) { pose in
                                Text(pose.shortName).tag(pose)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    if selection.bezel.pose.isLandscape {
                        Button {
                            model.toggleRotation()
                        } label: {
                            Label("Rotate", systemImage: "rotate.right")
                        }
                        .help("Rotate 180° to put the Dynamic Island on the other side")
                    }
                }

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
                .help("Click to play or pause")
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

    private func handleDrop(_ provider: NSItemProvider) -> Bool {
        print("Drop offered types: \(provider.registeredTypeIdentifiers)")

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadTransferable(type: URL.self) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let url):
                        loadAsync { try await model.load(from: url) }
                    case .failure(let error):
                        print("Could not load dropped URL: \(error)")
                        showToast(AppError.unsupportedFile.message)
                    }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            // The file only exists until the handler returns, so it is
            // copied somewhere that lasts while the recording is open.
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                var copy: URL?
                if let url {
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    let destination = directory.appendingPathComponent(url.lastPathComponent)
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: url, to: destination)
                        copy = destination
                    } catch {
                        print("Could not copy dropped movie: \(error)")
                    }
                } else if let error {
                    print("Could not load dropped movie: \(error)")
                }
                Task { @MainActor in
                    if let copy {
                        loadAsync { try await model.load(from: copy) }
                    } else {
                        showToast(AppError.unsupportedFile.message)
                    }
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                Task { @MainActor in
                    if let image = image as? NSImage {
                        load { try model.loadScreenshot(image) }
                    } else {
                        showToast(AppError.unsupportedFile.message)
                    }
                }
            }
            return true
        }

        return false
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

    private func exportProgressView(_ progress: Double) -> some View {
        VStack(spacing: 12) {
            Text("Exporting Video…")
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
        guard pendingResize != nil else {
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
