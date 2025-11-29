// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PlayListHiddenEditor: View {
    let editController: EditController
    let model: AudioModel

    @Environment(AudioRootModel.self) private var root

    var body: some View {
        MainRow(model: model, isSelected: false, cacheItemListModel: editController.cacheItemListModel)
            .padding(.leading, 32)
            .overlay(alignment: .bottomLeading) {
                Image(systemName: model.isGroupHidden ? "eye.slash.fill" : "eye.fill")
                    .padding(4)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.primary, .orange)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .onTapGesture {
                Task { await root.itemController.toggleGroupHidden(on: model.id) }
            }
    }
}

#Preview {
    PlayListHiddenEditor(editController: .preview, model: .preview)
        .environment(AudioRootModel.preview)
}
