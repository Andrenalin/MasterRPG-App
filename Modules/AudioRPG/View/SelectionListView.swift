// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SelectionListView: View {
    init(itemId: UUID? = nil) {
        self.itemId = itemId
        
        if let itemId {
            self._items = Query(filter: #Predicate<AudioDataModel> {
                $0.displayState == 0 && $0.parentId == itemId
            }, sort: \AudioDataModel.name, animation: .smooth)
        } else {
            self._items = Query(filter: #Predicate<AudioDataModel> {
                $0.displayState == 0
            }, sort: \AudioDataModel.name, animation: .smooth)
        }
    }
    
    let itemId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioRootModel.self) private var root

    @Query private var items: [AudioDataModel]
    
    var body: some View {
        ItemSelectionListView(editController: root.editController, items: items, module: AudioDataModel.typeId) { id in
            DetailRoute.selection(id)
        } row: { model in
            MainRowView(model: model)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    
    ManagedNavigationStack {
        SelectionListView(itemId: nil)
    }
}
