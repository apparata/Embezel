//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AVFoundation

/// A large preview over the grid. One item fills the window; several
/// (a multiple selection) are shown side by side in a strip that scrolls
/// horizontally.
///
/// Space, Escape, the close button or a click outside the images closes it.
/// The arrow keys go to the previous or next item: through the whole batch
/// for a single item, within the strip for several.
struct BatchPreview: View {

    let batch: BatchModel
    let ids: [BatchModel.Item.ID]

    /// The item shown, or centered in the strip.
    @Binding var currentID: BatchModel.Item.ID
    let onClose: () -> Void

    /// Moves to the previous or next item in the batch, for a single item.
    let onMove: (Int) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .contentShape(Rectangle())
                .onTapGesture {
                    onClose()
                }

            if ids.count > 1 {
                strip
            } else {
                BatchPreviewItem(batch: batch, id: currentID)
                    .padding(32)
            }
        }
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.space) {
            onClose()
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .upArrow]) { _ in
            move(-1)
            return .handled
        }
        .onKeyPress(keys: [.rightArrow, .downArrow]) { _ in
            move(1)
            return .handled
        }
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .help("Close Preview (Space or Esc)")
        .accessibilityLabel("Close Preview")
    }

    /// Space for an item's name below it in the strip.
    private static let captionHeight: CGFloat = 56

    /// The items side by side, each as large as fits in the window.
    private var strip: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 40) {
                        ForEach(ids, id: \.self) { id in
                            let size = itemSize(id, in: geometry.size)
                            BatchPreviewItem(batch: batch, id: id)
                                .frame(width: size.width, height: size.height)
                                .id(id)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 32)
                    // Center the strip when it is narrower than the window.
                    .frame(minWidth: geometry.size.width)
                }
                .scrollIndicators(.visible)
                .onAppear {
                    proxy.scrollTo(currentID, anchor: .center)
                }
                .onChange(of: currentID) { _, id in
                    withAnimation(.smooth) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    /// The size of an item in the strip: its framed output fitted into the
    /// window, less padding, plus its name.
    private func itemSize(_ id: BatchModel.Item.ID, in viewport: CGSize) -> CGSize {
        let canvas = batch.item(id)?.selection?.bezel.canvasSize ?? CGSize(width: 1, height: 2)
        let box = CGSize(
            width: max(viewport.width - 96, 100),
            height: max(viewport.height - 64 - Self.captionHeight, 100)
        )
        let scale = min(box.width / canvas.width, box.height / canvas.height)
        return CGSize(width: canvas.width * scale, height: canvas.height * scale + Self.captionHeight)
    }

    private func move(_ offset: Int) {
        guard ids.count > 1 else {
            onMove(offset)
            return
        }
        guard let index = ids.firstIndex(of: currentID) else {
            return
        }
        currentID = ids[min(max(index + offset, 0), ids.count - 1)]
    }
}

// MARK: - Item

/// One previewed item with its name: the full-size framed screenshot, or
/// the framed recording playing in a loop, muted. It keeps the framed
/// output's aspect ratio, so a strip can lay it out before it has loaded.
struct BatchPreviewItem: View {

    let batch: BatchModel
    let id: BatchModel.Item.ID

    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var loopTask: Task<Void, Never>?

    var body: some View {
        if let item = batch.item(id) {
            VStack(spacing: 16) {
                content(for: item)
                    .aspectRatio(item.selection?.bezel.canvasSize ?? CGSize(width: 1, height: 2), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                    if let selection = item.selection {
                        Text(selection.fileName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.middle)
            }
            // Reload when the item is framed differently.
            .task(id: loadKey) {
                await load()
            }
            .onDisappear {
                stopPlayback()
            }
        }
    }

    @ViewBuilder private func content(for item: BatchModel.Item) -> some View {
        if let player, item.kind == .video {
            PlayerView(player: player)
        } else if let image = image ?? item.thumbnail {
            Image(nsImage: image)
                .resizable()
        } else {
            ProgressView()
        }
    }

    private struct LoadKey: Equatable {
        let renderedURL: URL?
        let selection: Selection?
        let background: VideoBackground
    }

    private var loadKey: LoadKey {
        let item = batch.item(id)
        return LoadKey(
            renderedURL: item?.renderedURL,
            selection: item?.selection,
            background: batch.videoBackground
        )
    }

    private func load() async {
        stopPlayback()
        image = nil
        guard let item = batch.item(id), let selection = item.selection else {
            return
        }
        switch item.kind {
        case .image:
            guard let url = item.renderedURL else {
                return
            }
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            guard !Task.isCancelled else {
                return
            }
            image = loaded
        case .video:
            guard let url = item.originalURL,
                  let assets = await BezelAssets.shared.loadAssets(for: selection.bezel) else {
                return
            }
            let asset = AVURLAsset(url: url)
            guard let composition = try? await VideoBezelComposer.makeComposition(
                asset: asset,
                selection: selection,
                bezelImage: assets.image,
                screenMask: assets.mask,
                background: batch.videoBackground
            ), !Task.isCancelled else {
                return
            }
            startPlayback(asset: asset, composition: composition)
        }
    }

    private func startPlayback(asset: AVAsset, composition: AVVideoComposition) {
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        loopTask = Task { [player] in
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification,
                object: item
            ) {
                await player.seek(to: .zero)
                player.play()
            }
        }
        self.player = player
        player.play()
    }

    private func stopPlayback() {
        loopTask?.cancel()
        loopTask = nil
        player?.pause()
        player = nil
    }
}
