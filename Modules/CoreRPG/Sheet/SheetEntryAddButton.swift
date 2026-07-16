// @copyright André Trettin

import SwiftUI

struct SheetEntryAddButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let onlyIcon: Bool

    var body: some View {
        if entryDataEditable != nil {
            Button {
                var entryId: UUID?
                withAnimation {
                    entryId = rootModel.addNewEntry(in: parentModel)
                    rootModel.updateParent(parentModel)
                } completion: {
                    rootModel.setScrollEntryId(source: parentModel.source, entryId: entryId)
                }
            } label: {
                Label {
                    Text("New entry in \(parentModel.name.withoutLink())", bundle: .module)
                } icon: {
                    Image(systemName: "note.text.badge.plus")
                        .imageScale(.large)
                        .foregroundStyle(.foreground, .tint)
                }
                .applyIf(onlyIcon) {
                    $0.labelStyle(.iconOnly)
                }
            }
            .applyIf(onlyIcon) {
                $0.borderLessTVBottonStyle()
                    .padding(4)
                    .contentShape(.circle)
            }
        }
    }

    var entryDataEditable: (any EntryDataEditable)? {
        rootModel.entryDataEditable(for: parentModel.source)
    }
}

#Preview("Add Entry") {
    SheetEntryAddButton(rootModel: .fake, parentModel: SheetButtonPreviewData.parent, onlyIcon: false)
        .padding()
}
