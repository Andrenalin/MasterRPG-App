// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AddtionalEntryRow: View, Equatable {
    let entryId: UUID
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        VStack(alignment: .leading) {
            HStack {
                Text(entry.type.title)
                
                EntryListDiceRow(itemId: model.id, entryId: entryId)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var model: ValueModel {
        root.editController.model
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

    AddtionalEntryRow(entryId: root.editController.model.entries[0].id)
}
