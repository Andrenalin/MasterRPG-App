// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct InspectorRootView: View {
    let model: AudioDataModel
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioRootModel.self) private var root

    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]

    var body: some View {
        LinkItemListView(editController: root.editController, items: items, parentModel: model) { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    
    NavigationStack {
        InspectorRootView(model: models.first!)
    }
}
