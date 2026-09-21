// @copyright André Trettin

import SwiftUI

struct SheetEntryDeleteButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let onlyIcon: Bool

    var body: some View {
        Button(role: .destructive) {
            withAnimation {
                rootModel.removeEntry(entryModel: entryModel, from: parentModel)
            }
        } label: {
            Label {
                Text("Delete \(entryModel.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
            .applyIf(onlyIcon) {
                $0.labelStyle(.iconOnly)
            }
        }
        .foregroundStyle(.white, .red, .red)
        .borderLessTVButtonStyle()
        .applyIf(onlyIcon) { $0.frame(minWidth: 44, minHeight: 44) }
        .keyboardShortcutAll("r", modifiers: .shift)
    }
}

#Preview("Delete Entry") {
    SheetEntryDeleteButton(
        rootModel: .fake,
        parentModel: SheetButtonPreviewData.parent,
        entryModel: SheetButtonPreviewData.entry,
        onlyIcon: false
    )
    .padding()
}
