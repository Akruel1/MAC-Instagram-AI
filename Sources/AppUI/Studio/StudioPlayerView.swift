import SwiftUI
import AVKit
import AppKit

/// AppKit-backed preview. Avoids SwiftUI `VideoPlayer` / `_AVKit_SwiftUI`, which aborted
/// during metadata init on this SPM-packaged macOS app (see crash report 2026-11-16).
struct StudioPlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}
