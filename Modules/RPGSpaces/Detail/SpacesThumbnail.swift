// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SpacesThumbnail: View {
    let itemId: UUID

    @Environment(SpaceRoot.self) private var root

    var body: some View {
        ThumbnailItem(model: root.itemController.itemOrEmpty(for: itemId))
            .padding(.leading, 32)
            .overlay(alignment: .bottomLeading) {
                Image(systemName: (root.itemController.itemOrEmpty(for: itemId).isGroupHidden) ? "eye.slash.fill" : "eye.fill")
                    .imageScale(.small)
                    .padding(2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.primary, .orange)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .onTapGesture {
                Task { await root.itemController.toggleGroupHidden(on: itemId) }
            }
    }
}

#Preview {
    SpacesThumbnail(itemId: SpaceModel.previewId)
        .environment(SpaceRoot.preview)
}
