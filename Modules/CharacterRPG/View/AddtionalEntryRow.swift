// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AddtionalEntryRow: View, Equatable {
    let itemId: UUID
    let entryId: UUID
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        VStack(alignment: .leading) {
            HStack {
                Text(entry.type.title)
                
                EntryListDiceRow(itemId: itemId, entryId: entryId)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var model: ValueModel {
        root.itemController.itemOrEmpty(for: itemId)
    }
    
    private var entry: ValueEntryModel {
        model[entryId]
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entryId == rhs.entryId
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(CharacterRootModel.self) var root
    
    AddtionalEntryRow(itemId: root.itemController.itemDataModel.items.first!, entryId: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first!).entries[0].id)
}
