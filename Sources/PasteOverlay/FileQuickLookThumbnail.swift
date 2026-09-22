import AppKit
import QuickLookThumbnailing
import SwiftUI

struct FileQuickLookThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable().scaledToFit()
            .task(id: url) {
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 240, height: 200),
                                                          scale: 2, representationTypes: .thumbnail)
                let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                if !Task.isCancelled { image = representation?.nsImage }
            }
    }
}
