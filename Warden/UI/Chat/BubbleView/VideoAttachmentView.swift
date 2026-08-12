import AVKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Simple inline video preview + actions.
///
/// Generated videos are transient. Only readable, local regular files can be played or exported.
struct VideoAttachmentView: View {
    let videoURL: URL
    var maxWidth: CGFloat = 360

    @State private var player: AVPlayer? = nil
    @State private var showInFinderError: String? = nil

    private var isAvailable: Bool {
        VideoAttachmentSupport.isUsableLocalVideo(videoURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if VideoAttachmentSupport.shouldDisplayPlayer(playerExists: player != nil, videoURL: videoURL),
                   let player {
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
                    ContentUnavailableView(
                        "Video Unavailable",
                        systemImage: "video.slash",
                        description: Text("This generated video is no longer available on this Mac.")
                    )
                        .frame(width: maxWidth, height: maxWidth * 9/16)
                        .accessibilityLabel("Generated video unavailable")
                }
            }

            HStack(spacing: 10) {
                Button("Reveal") {
                    revealInFinder(videoURL)
                }
                .buttonStyle(.bordered)
                .disabled(!isAvailable)
                .accessibilityHint("Reveals the generated video in Finder when it is available")

                Button("Save As…") {
                    saveAs(videoURL)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isAvailable)
                .accessibilityHint("Saves a copy without replacing an existing file")

                Spacer()
            }
        }
        .onAppear {
            if player == nil, isAvailable {
                player = AVPlayer(url: videoURL)
            }
        }
        .alert(item: $showInFinderError) { msg in
            Alert(title: Text("Video"), message: Text(msg), dismissButton: .default(Text("OK")))
        }
    }

    private func revealInFinder(_ url: URL) {
        #if os(macOS)
        guard VideoAttachmentSupport.isUsableLocalVideo(url) else {
            player = nil
            showInFinderError = "This generated video is unavailable."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    private func saveAs(_ url: URL) {
        #if os(macOS)
        guard VideoAttachmentSupport.isUsableLocalVideo(url) else {
            player = nil
            showInFinderError = "This generated video is unavailable."
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent
        panel.title = "Save Video"
        panel.message = "Choose where to save the video"

        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            guard let errorMessage = VideoAttachmentSupport.exportError(source: url, destination: dest) else {
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                } catch {
                    showInFinderError = "The video could not be saved to the selected location."
                }
                return
            }
            showInFinderError = errorMessage
        }
        #endif
    }
}

enum VideoAttachmentSupport {
    static func isUsableLocalVideo(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        let path = url.path
        guard FileManager.default.isReadableFile(atPath: path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0 else {
            return false
        }
        return true
    }

    static func shouldDisplayPlayer(playerExists: Bool, videoURL: URL) -> Bool {
        playerExists && isUsableLocalVideo(videoURL)
    }

    /// Returns a localized-safe explanation when a copy must not proceed.
    static func exportError(source: URL, destination: URL) -> String? {
        guard isUsableLocalVideo(source) else {
            return "This generated video is unavailable."
        }
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            return "Choose a different location for the saved copy."
        }
        if (try? destination.checkResourceIsReachable()) == true {
            return "A file already exists at the selected location. Choose a different name."
        }
        return nil
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
