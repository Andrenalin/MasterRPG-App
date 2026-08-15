// @copyright André Trettin

import SwiftUI

struct SheetEntryAddGroupButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let onlyIcon: Bool

    var body: some View {
        Button {
            Task {
                let entryId = await rootModel.addNewGroup(in: parentModel)
                withAnimation {
                    rootModel.updateParent(parentModel)
                } completion: {
                    rootModel.setScrollEntryId(source: parentModel.source, entryId: entryId)
                }
            }
        } label: {
            Label {
                Text("New group in \(parentModel.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "plus.square.fill.on.square.fill")
            }
            .applyIf(onlyIcon) {
                $0.labelStyle(.iconOnly)
            }
        }
    }
}

#Preview {
    SheetEntryAddGroupButton(rootModel: .fake, parentModel: SheetModel.empty, onlyIcon: false)
        .padding()
}
