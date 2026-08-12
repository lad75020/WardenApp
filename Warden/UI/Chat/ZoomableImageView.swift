
import SwiftUI
import os

enum ImageExportFormat: Equatable {
    case png
    case jpeg

    static func forDestination(_ url: URL) -> ImageExportFormat {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        default: return .png
        }
    }

    func data(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        switch self {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    }
}

struct ZoomableImageView: View {
    let image: NSImage
    let imageAspectRatio: CGFloat
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var saveError: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .clipped()
                    .padding(0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.25), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                withAnimation {
                                    scale = scale > 1.0 ? 1.0 : 2.0
                                    if scale == 1.0 {
                                        offset = .zero
                                        lastOffset = .zero
                                        lastScale = 1.0
                                    }
                                }
                            }
                    )
            }

            Group {
                HStack {
                    Button(action: {
                        withAnimation {
                            scale = min(scale + 0.25, 5.0)
                        }
                    }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .accessibilityLabel("Zoom in")
                    .keyboardShortcut("=", modifiers: [])
                    .keyboardShortcut("+", modifiers: [])

                    Button(action: {
                        withAnimation {
                            scale = max(scale - 0.25, 0.25)
                        }
                    }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .accessibilityLabel("Zoom out")
                    .keyboardShortcut("-", modifiers: [])

                    Button(action: {
                        withAnimation {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                            lastScale = 1.0
                        }
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Reset image zoom and position")

                    Button(action: {
                        saveImage()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Save image as")
                    .keyboardShortcut("s", modifiers: .command)

                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close image viewer")
                    .keyboardShortcut("q", modifiers: .command)
                }
                .padding(8)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding(10)
        }
        .aspectRatio(imageAspectRatio, contentMode: .fill)
        .padding(0)
        .frame(minWidth: imageAspectRatio > 1.4 ? 800 : nil)
        .alert("Image Attachment", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "image.png"
        savePanel.title = "Save Image"
        savePanel.message = "Choose where to save the image"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                guard (try? url.checkResourceIsReachable()) != true else {
                    saveError = "A file already exists at the selected location. Choose a different name."
                    return
                }
                guard let imageData = ImageExportFormat.forDestination(url).data(for: image) else {
                    saveError = "The image could not be prepared for saving."
                    return
                }

                do {
                    try imageData.write(to: url)
                    #if DEBUG
                    WardenLog.app.debug("Image saved successfully")
                    #endif
                }
                catch {
                    saveError = "The image could not be saved to the selected location."
                }
            }
        }
    }
}
