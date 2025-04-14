// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct EntryThumbnail: View {
    let root: MapRoot
    let item: MapModel
    let entryId: UUID

    @State private var image: AKImage?

    var body: some View {
        @Bindable var model = item
        Group {
            if let image {
                Image(akImage: image)
                    .resizable()
                    .frame(width: 64, height: 64)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .frame(width: 64, height: 64)
            }
        }
        .onChange(of: model[entryId].coordinates, initial: true) {
            resetImage()
        }
    }

    func resetImage() {
        Task.detached(priority: .userInitiated) {
            await root.cacheController.thumbnailId(for: item, entryId: entryId)
            let newimage = await root.cacheController.thumbnail(for: entryId)
            Task { @MainActor in
                withAnimation { image = newimage }
            }
        }
    }
}
