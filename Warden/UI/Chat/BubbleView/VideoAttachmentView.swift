import AVKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Simple inline video preview + actions.
///
/// Expects a local file URL (file://). Remote URLs may work, but we don't attempt caching.
struct VideoAttachmentView: View {
    let videoURL: URL
    var maxWidth: CGFloat = 360

    @State private var player: AVPlayer? = nil
    @State private var showInFinderError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let player {
                    #if os(macOS)
                    AVPlayerViewRepresentable(player: player)
                        .frame(maxWidth: maxWidth)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(8)
                    #else
                    VideoPlayer(player: player)
                        .frame(maxWidth: maxWidth)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(8)
                    #endif
                } else {
                    ProgressView()
                        .frame(width: maxWidth, height: maxWidth * 9/16)
                }
            }

            HStack(spacing: 10) {
                Button("Reveal") {
                    revealInFinder(videoURL)
                }
                .buttonStyle(.bordered)

                Button("Save As…") {
                    saveAs(videoURL)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: videoURL)
            }
        }
        .alert(item: $showInFinderError) { msg in
            Alert(title: Text("Video"), message: Text(msg), dismissButton: .default(Text("OK")))
        }
    }

    private func revealInFinder(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    private func saveAs(_ url: URL) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent
        panel.title = "Save Video"
        panel.message = "Choose where to save the video"

        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                // If saving to the same place, no-op.
                if dest.standardizedFileURL == url.standardizedFileURL { return }
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                showInFinderError = "Failed to save video: \(error.localizedDescription)"
            }
        }
        #endif
    }
}

#if os(macOS)
/// Avoid SwiftUI's `VideoPlayer` (AVKit_SwiftUI) on macOS: we've seen runtime crashes inside
/// `_AVKit_SwiftUI` metadata init on some OS builds. Using `AVPlayerView` directly is more stable.
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .floating
        v.videoGravity = .resizeAspect
        v.player = player
        return v
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
#endif

extension String: @retroactive Identifiable {
    public var id: String { self }
}
