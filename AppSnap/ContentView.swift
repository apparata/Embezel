//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import Constructs

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

    // MARK: - Body

    var body: some View {
        VStack {
            if model.screenshot != nil {
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
                    Text("Drop iPhone screenshot here")
                        .font(.title2)
                }
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowReflection(window: $window))
        .onChange(of: window) {
            resizeWindowIfNeeded()
        }
        // Open files in this window instead of creating a new one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onChange(of: model.compositedImage?.size) { _, size in
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

        // MARK: - Drop Destination (NSImage)

        .dropDestination(for: NSImage.self) { items, _ in
            guard let image = items.first else {
                return false
            }
            return load { try model.loadScreenshot(image) }
        }

        // MARK: - Drop Destination (URL)

        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else {
                return false
            }
            return load { try model.loadScreenshot(from: url) }
        }

        // MARK: - On Open URL

        .onOpenURL { url in
            load { try model.loadScreenshot(from: url) }
        }

        // MARK: - File Importer

        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    load { try model.loadScreenshot(from: url, isSecurityScoped: true) }
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
                    if let image = model.compositedImage, let selection = model.selection {
                        exportImage(image, name: selection.fileName)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        Group {
            if let startDate {
                TimelineView(.animation) { context in
                    deviceView
                        .scaleEffect(isDoneBouncing ? 1.0 : 0.9)
                        .visualEffect { content, proxy in
                            content
                                .colorEffect(removeEffect(
                                    t: -startDate.timeIntervalSinceNow * 2,
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
            resizeWindowIfNeeded()
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
            }
        }
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
        }
    }

    // MARK: - Load

    /// Runs a load action and shows a toast if it fails.
    @discardableResult
    private func load(_ action: () throws -> Void) -> Bool {
        do {
            try action()
        } catch let error as AppError {
            showToast(error.message)
            return false
        } catch {
            showToast("Unexpected error")
            return false
        }
        bounce()
        withAnimation(.smooth) {
            footerOpacity = 1
        }
        return true
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

    // MARK: - Window Resizing

    /// Smallest size of the window's content area. Narrower than 400 pt and
    /// the toolbar buttons overflow into a menu.
    static let minimumSize = CGSize(width: 400, height: 360)

    /// Resizes the window on the next run loop pass, after SwiftUI has laid
    /// out the controls for the new composite.
    private func scheduleResize(toFit size: CGSize?) {
        pendingResize = size
        DispatchQueue.main.async {
            resizeWindowIfNeeded()
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
        window.setFrame(frame, display: true, animate: true)
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
