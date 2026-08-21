// @copyright André Trettin

import SwiftUI
import TipKit

struct SheetEntryAddButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let onlyIcon: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        if entryDataEditable != nil {
            Button {
                var entryId: UUID?
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    entryId = rootModel.addNewEntry(in: parentModel)
                    rootModel.updateParent(parentModel)
                } completion: {
                    rootModel.setScrollEntryId(source: parentModel.source, entryId: entryId)
                }
                if entryId != nil {
                    MasterRPGTips.refreshEligibility(rootManager: rootModel.rootManager)
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
            .popoverTip(
                parentModel.level == 0 && parentModel.entries.isEmpty
                    ? MasterRPGTips.firstEntry
                    : nil
            )
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
