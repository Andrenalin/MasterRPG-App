// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct CharacterDetailSheet: View {
    let item: ItemRowTreeModel
    
    @Environment(CharacterRootModel.self) private var root
    @Environment(\.routeActions) private var routeActions
    
    var body: some View {
        CharacterSheet(model: model, showTopImage: true, dismissAction: nil)
            .environment(\.showGame, true)
            .overlay(alignment: .topTrailing) {
                Button {
                    routeActions.routePage(root.itemController.itemDataModel.networkModule, item.model.itemId, item.model.entryId)
                } label: {
                    Image(systemName: root.itemController.itemDataModel.networkModule.icon)
                }
                .padding()
            }
    }
    
    var model: ValueModel {
        root.itemController.itemOrEmpty(for: item.model.itemId)
    }
}

#Preview {
    CharacterDetailSheet(item: .preview)
        .environment(CharacterRootModel.previewWithData)
}
