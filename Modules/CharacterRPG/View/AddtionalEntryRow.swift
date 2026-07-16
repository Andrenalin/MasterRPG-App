// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AddtionalEntryRow: View, Equatable {
    let source: ItemRowModel
    let entry: any EntryDataAccessable
    let textModel: LinkHighlightTextModel?
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 4) {
                
                Image(systemName: typeIcon)
                    .imageScale(.small)
                    .foregroundStyle(.foreground, .tint)
                    .accessibilityHidden(true)
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
    
    private var valueEntry: ValueEntryModel {
        entry as? ValueEntryModel ?? model[entryId]
    }
    
    private var entryId: UUID {
        source.entryId ?? UUID()
    }
    
    private var typeIcon: String {
        guard valueEntry.valueId != nil else {
            return valueEntry.type.icon
        }
        return "square.on.square.squareshape.controlhandles"
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entryId == rhs.entryId
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(CharacterRootModel.self) var root
    
    AddtionalEntryRow(source: ItemRowModel(itemId: root.itemController.itemDataModel.items.first!, entryId: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first!).entries[0].id, typeId: .value), entry: ValueEntryModel.empty, textModel: LinkHighlightTextModel(linkControllable: nil, text: "Hello Links", highlightedText: "in", toggler: nil, shareResult: nil, editAction: nil))
}
