// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct AddtionalEntryRow: View, Equatable {
    let source: ItemRowModel
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
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
    }
    
    private var model: MapModel {
        root.itemController.itemOrEmpty(for: source.itemId)
    }
    
    private var entry: MapEntryModel {
        model[entryId]
    }
    
    private var entryId: UUID {
        source.entryId ?? UUID()
    }
    
    private var pinsCounter: Int {
        let entryRect = entry.rect
        return model.mapPins.filter { entryRect.contains($0.location) }.count
        
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source
    }
}

//#Preview(traits: .mockData) {
//    @Previewable @Environment(MapRootModel.self) var root
//
//    AddtionalEntryRow(entryId: root.editController.model.entries[0].id)
//}
