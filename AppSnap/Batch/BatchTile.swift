//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// One item in the batch grid: the framed thumbnail, the file name and
/// badges. Clicks and drags are handled by a `BatchDragSource` on top of
/// the thumbnail.
struct BatchTile: View {

    let item: BatchModel.Item
    let isSelected: Bool
    let dragFiles: () -> [PromisedFile]
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onRotate: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                BatchDragSource(files: dragFiles, onClick: onClick)

                badges
            }
            .frame(height: 150)

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            if let message = statusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { isHovering = $0 }
        .help(item.originalURL?.lastPathComponent ?? item.name)
    }

    @ViewBuilder private var preview: some View {
        if let thumbnail = item.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(item.isRendering ? 0.6 : 1)
                .overlay {
                    if item.isRendering {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
        } else {
            switch item.status {
            case .loading, .ready:
                ProgressView()
                    .controlSize(.small)
            case .unsupported, .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Badges and the rotate button sit above the drag source, so they get
    /// their own clicks.
    private var badges: some View {
        VStack {
            HStack {
                if item.kind == .video {
                    Label(durationText, systemImage: "video.fill")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .help("Screen recording; encoded when dragged out or exported")
                }
                Spacer()
                if item.override != nil {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .padding(4)
                        .background(.regularMaterial, in: Circle())
                        .help("Has its own device setting")
                }
            }
            Spacer()
            HStack {
                Spacer()
                if isHovering, item.selection?.bezel.pose.isLandscape == true {
                    Button {
                        onRotate()
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    .buttonStyle(.borderless)
                    .padding(4)
                    .background(.regularMaterial, in: Circle())
                    .help("Rotate 180°")
                }
            }
        }
        .padding(4)
    }

    private var durationText: String {
        guard let duration = item.duration, duration.isFinite else {
            return ""
        }
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var statusMessage: String? {
        switch item.status {
        case .unsupported(let message), .failed(let message):
            message
        case .loading, .ready:
            nil
        }
    }
}
