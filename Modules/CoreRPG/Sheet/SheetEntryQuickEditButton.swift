// @copyright André Trettin

import SwiftUI

struct SheetEntryQuickEditButton: View {
    let rootModel: SheetRootModel
    let entryModel: SheetModel
    let parentModel: SheetModel
    let onlyIcon: Bool

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            if let entryDataEditable = rootModel.entryDataEditable(for: entryModel.source) {
                rootModel.editorModel.parentModel = parentModel
                navigator.navigate(to: entryDataEditable.quickEditorDestination(itemRowModel: entryModel.source))
            }
        } label: {
            Label {
                Text("Quick Editor for \(parentModel.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "table.badge.more")
                    .imageScale(.large)
                    .foregroundStyle(.foreground, .tint)
            }
            .applyIf(onlyIcon) {
                $0.labelStyle(.iconOnly)
            }
        }
        .borderLessTVBottonStyle()
    }
}

#Preview("Quick Edit Entry") {
    SheetEntryQuickEditButton(
        rootModel: .fake,
        entryModel: SheetButtonPreviewData.entry,
        parentModel: SheetButtonPreviewData.parent,
        onlyIcon: false
    )
    .padding()
}
