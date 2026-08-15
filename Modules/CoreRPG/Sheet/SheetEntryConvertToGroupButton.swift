// @copyright André Trettin

import SwiftUI

struct SheetEntryConvertToGroupButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let onlyIcon: Bool

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: InternalRoute.convertGroup(source: entryModel.source), method: .sheet)
        } label: {
            Label {
                Text("Convert \(entryModel.name.withoutLink()) to group", bundle: .module)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .applyIf(onlyIcon) {
                $0.labelStyle(.iconOnly)
            }
        }
    }
}

#Preview("Convert to Group") {
    SheetEntryConvertToGroupButton(
        rootModel: .fake,
        parentModel: SheetButtonPreviewData.parent,
        entryModel: SheetButtonPreviewData.entry,
        onlyIcon: false
    )
    .padding()
}
