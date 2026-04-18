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

    // MARK: - Body

    var body: some View {
        VStack {
            if model.screenshot != nil {
                VStack(spacing: 20) {
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

                    Picker(model.selectedDeviceAndVariant.device.name, selection: $model.selectedDeviceAndVariant) {
                        ForEach(model.candidates, id: \.self) { section in
                            Section(section[0].device.name) {
                                ForEach(section, id: \.self) { candidate in
                                    Text(candidate.variant)
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                    .opacity(footerOpacity)
                    .onChange(of: model.selectedDeviceAndVariant) { _, _ in
                        try? model.makeComposite()
                    }
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
            do {
                try model.loadScreenshot(image)
                try model.makeComposite()
            } catch AppError.unsupportedScreenshotSize {
                toastMessage = "Unsupported screenshot size"
                toastModel.showToast()
                return false
            } catch {
                toastMessage = "Unexpected error"
                toastModel.showToast()
                return false
            }
            bounce()
            withAnimation(.smooth) {
                footerOpacity = 1
            }
            return true
        }

        // MARK: - Drop Destination (URL)

        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first {
                do {
                    try model.loadScreenshot(from: url)
                    try model.makeComposite()
                } catch AppError.unsupportedScreenshotSize {
                    toastMessage = "Unsupported screenshot size"
                    toastModel.showToast()
                    return false
                } catch {
                    toastMessage = "Unexpected error"
                    toastModel.showToast()
                    return false
                }
                bounce()
                withAnimation(.smooth) {
                    footerOpacity = 1
                }
            }
            return true
        } isTargeted: { isTargeted in
            //print("Is targeted: \(isTargeted)")
        }

        // MARK: - On Open URL

        .onOpenURL { url in
            if url.pathExtension == "png" {
                do {
                    try model.loadScreenshot(from: url)
                    try model.makeComposite()
                } catch AppError.unsupportedScreenshotSize {
                    toastMessage = "Unsupported screenshot size"
                    toastModel.showToast()
                    return
                } catch {
                    toastMessage = "Unexpected error"
                    toastModel.showToast()
                    return
                }
                withAnimation(.smooth) {
                    footerOpacity = 1
                }
            }
        }

        // MARK: - File Importer

        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image, .movie, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }
                if ["png", "jpg"].contains(url.pathExtension) {
                    do {
                        try model.loadScreenshot(from: url, isSecurityScoped: true)
                        try model.makeComposite()
                    } catch AppError.unsupportedScreenshotSize {
                        toastMessage = "Unsupported screenshot size"
                        toastModel.showToast()
                        return
                    } catch {
                        toastMessage = "Unexpected error"
                        toastModel.showToast()
                        return
                    }
                    bounce()
                    withAnimation(.smooth) {
                        footerOpacity = 1
                    }
                } else if ["mp4", "mov"].contains(url.pathExtension) {
                    Task {
                        do {
                            try await model.makeVideo(from: url)
                        } catch {
                            dump(error)
                        }
                    }
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
                    if let image = model.compositedImage {
                        exportImage(image)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Device View

    @ViewBuilder var deviceView: some View {
        if let compositedImage = model.compositedImage {
            Image(nsImage: compositedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .onDrag {
                    // Save the image temporarily to a file URL
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(model.selectedDeviceAndVariant.device.name).png")

                    if let tiffData = compositedImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: tempURL)
                    }

                    guard let provider = NSItemProvider(contentsOf: tempURL) else {
                        fatalError()
                    }
                    return provider.applying { provider in
                        provider.suggestedName = "\(model.selectedDeviceAndVariant.device.name) - \(model.selectedDeviceAndVariant.variant)"
                    }
                }
        }
    }

    // MARK: - Export Image

    func exportImage(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(model.selectedDeviceAndVariant.device.name).png"
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
