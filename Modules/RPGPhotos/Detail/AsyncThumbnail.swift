// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AsyncThumbnail<Content: View>: View {
    init(model: PhotoModel, size: CGSize, @ViewBuilder content: @escaping (AKImage?) -> Content) {
        self.model = model
        self.size = size
        self.content = content
    }

    let model: PhotoModel
    let size: CGSize
    let content: (AKImage?) -> Content

    @Environment(PhotoRoot.self) private var root

    @State private var image: AKImage?

    var body: some View {
        @Bindable var model = model

        content(image)
            .onChange(of: model.fileUrl, initial: true) {
                loadImage()
            }
    }

    private func loadImage() {
        Task.detached(priority: .userInitiated) {
            await root.cacheController.thumbnailId(for: model.id, with: model.fileUrl)
            let newImage = await root.cacheController.thumbnail(for: model.id)
            Task { @MainActor in
                withAnimation { image = newImage }
            }
        }
    }
}

#Preview {
    AsyncThumbnail(model: .preview, size: CGSize(width: 128, height: 128)) {
        if let image = $0 {
            Image(akImage: image)
        } else {
            Text("No image found", bundle: .module)
        }
    }
    .environment(PhotoRoot.preview)
}
