//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AVFoundation

/// Shows a player's video without any controls. Unlike `AVPlayerView`, the
/// background is clear, so transparent video shows the window behind it.
struct PlayerView: NSViewRepresentable {

    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

// MARK: - Player Layer View

final class PlayerLayerView: NSView {

    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = .clear
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        playerLayer
    }
}
