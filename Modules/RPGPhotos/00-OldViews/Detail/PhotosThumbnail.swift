// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PhotosThumbnail: View {
    let itemId: UUID

    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        ThumbnailItem(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .padding(.horizontal, 32)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    Task { await root.itemController.toggleGroupHidden(on: itemId) }
                } label: {
                    Image(systemName: (root.itemController.itemOrEmpty(for: itemId).isGroupHidden) ? "eye.slash.fill" : "eye.fill")
                        .imageScale(.small)
                        .padding(2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .orange)
                        .contentTransition(.symbolEffect(.replace.wholeSymbol))
                }
                .borderLessTVBottonStyle()
                .contentShape(.rect)
                .offset(x: valueFor(iOS: 8, macOS: 8, tvOS: 8, visionOS: 16))
            }
    }
}

#Preview {
    PhotosThumbnail(itemId: PhotoModel.previewId)
        .environment(PhotoRootModel.preview)
}
