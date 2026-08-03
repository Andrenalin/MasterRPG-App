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
            if onlyIcon {
                Image(systemName: "arrow.triangle.2.circlepath")
            } else {
                Label {
                    Text("Convert \(entryModel.name.withoutLink()) to group", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
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
