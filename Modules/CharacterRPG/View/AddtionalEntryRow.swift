// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AddtionalEntryRow: View, Equatable {
    let source: ItemRowModel
    let textModel: LinkHighlightTextModel?
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        let _ = Self._printChanges()
        VStack(alignment: .leading) {
            HStack(spacing: 4) {
                
                Image(systemName: entry.type.icon)
                    .imageScale(.small)
                    .foregroundStyle(.foreground, .tint)
                    .padding(4)
                    .background {
                        Circle().stroke(
                            root.configurable.module.tint.opacity(0.3))
                    }
                
                if let textModel {
                    LinkHighlightTextView(model: textModel)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            EntryListDiceRow(itemId: source.itemId, entryId: entryId)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var model: ValueModel {
        root.itemController.itemOrEmpty(for: source.itemId)
    }
    
    private var entry: ValueEntryModel {
        model[entryId]
    }
    
    private var entryId: UUID {
        source.entryId ?? UUID()
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entryId == rhs.entryId
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(CharacterRootModel.self) var root
    
    AddtionalEntryRow(source: ItemRowModel(itemId: root.itemController.itemDataModel.items.first!, entryId: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first!).entries[0].id, typeId: .value), textModel: LinkHighlightTextModel(linkControllable: nil, text: "Hello Links", highlightedText: "in", toggler: nil, shareResult: nil, editAction: nil))
}
