// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct AddtionalEntryRow: View, Equatable {
    let itemId: UUID
    let entryId: UUID
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        @Bindable var model = model
        VStack(alignment: .trailing) {
            HStack {
                Toggle(isOn: $model[entryId].isShown) {
                    Text("Shown", bundle: .module)
                }
                .labelsHidden()
                
                Text("Shown", bundle: .module)
            }
            Text("\(pinsCounter) pins", bundle: .module)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    
    private var model: MapModel {
        root.itemController.itemOrEmpty(for: itemId)
    }
    
    private var entry: MapEntryModel {
        model[entryId]
    }
    
    private var pinsCounter: Int {
        let entryRect = entry.rect
        return model.mapPins.filter { entryRect.contains($0.location) }.count
        
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entryId == rhs.entryId
    }
}

//#Preview(traits: .mockData) {
//    @Previewable @Environment(MapRootModel.self) var root
//
//    AddtionalEntryRow(entryId: root.editController.model.entries[0].id)
//}
