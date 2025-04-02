//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import Constructs

struct ContentView: View {

    @State private var model = ContentModel()

    @State private var isDoneBouncing = true

    @State private var isImporterPresented = false

    var body: some View {
        VStack {
            if model.screenshot != nil {
                VStack(spacing: 20) {
                    deviceView
                        .scaleEffect(isDoneBouncing ? 1.0 : 0.9)
                    Text(model.device.name)
                    Picker("", selection: $model.variant) {
                        ForEach(model.device.variants, id: \.self) { variant in
                            Text(variant)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 150)
                    .onChange(of: model.variant) { _, _ in
                        model.makeComposite()
                    }
                }
                .padding(40)
            } else {
                VStack {
                    Text("Drop iPhone screenshot here")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: NSImage.self) { items, _ in
            if let image = items.first {
                switch image.size {
                case Device.iPhone16Pro.screenSize: break
                case Device.iPhone16ProMax.screenSize: break
                default: return false
                }
                model.loadScreenshot(image)
                model.makeComposite()
                bounce()
            }
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first {
                model.loadScreenshot(from: url)
                model.makeComposite()
                bounce()
            }
            return true
        } isTargeted: { isTargeted in
            //print("Is targeted: \(isTargeted)")
        }
        .onOpenURL { url in
            if url.pathExtension == "png" {
                model.loadScreenshot(from: url)
                model.makeComposite()
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.loadScreenshot(from: url, isSecurityScoped: true)
                    model.makeComposite()
                    bounce()
                }
            case .failure(let error):
                dump(error)
            }
        }
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
                    model.clear()
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

    @ViewBuilder var deviceView: some View {
        if let compositedImage = model.compositedImage {
            Image(nsImage: compositedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .onDrag {
                    // Save the image temporarily to a file URL
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(model.device.name).png")

                    if let tiffData = compositedImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: tempURL)
                    }

                    guard let provider = NSItemProvider(contentsOf: tempURL) else {
                        fatalError()
                    }
                    return provider.applying { provider in
                        provider.suggestedName = "\(model.device.name) - \(model.variant)"
                    }
                }
        }
    }

    func exportImage(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(model.device.name).png"
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

    private func bounce() {
        isDoneBouncing = false
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            isDoneBouncing = true
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
