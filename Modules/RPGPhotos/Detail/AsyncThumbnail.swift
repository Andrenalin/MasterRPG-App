// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AsyncThumbnail: View {
    let model: PhotoModel
    let size: CGSize
    let color: Color

    @Environment(PhotoRoot.self) private var root

    @State private var image: AKImage?

    var body: some View {
        @Bindable var model = model
        Group {
            if let image {
                Image(akImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                color
            }
        }
        .onChange(of: model.fileUrl, initial: true) {
            loadImage()
        }
    }

    private func loadImage() {
        let cacheController = root.cacheController
        let id = model.id
        let fileUrl = model.fileUrl
        let loaderTask = Task.detached(priority: .userInitiated) {
            await cacheController.thumbnailId(for: id, with: fileUrl)
        }

        Task { @MainActor in
            let _ = await loaderTask.result
            let newImage = await cacheController.thumbnail(for: id)
            withAnimation { self.image = newImage }
        }
    }
}

#Preview {
    AsyncThumbnail(model: .preview, size: CGSize(width: 128, height: 128), color: .gray)
        .environment(PhotoRoot.preview)
}
