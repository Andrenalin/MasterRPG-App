// @copyright André Trettin

import SwiftUI

struct SheetEntryTakeOverButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let onlyIcon: Bool

    var body: some View {
        Button {
            let animation: Animation? = .smooth
            withAnimation(animation) {
                rootModel.commitAIEntry(entryModel, parent: parentModel)
            }
        } label: {
            Label {
                Text("Take Over", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
            .applyIf(onlyIcon) {
                $0.labelStyle(.iconOnly)
                    .imageScale(.large)
                    .padding(8)
                    .minimumHitArea()
            }
        }
        .applyIf(onlyIcon) {
            $0
                .buttonStyle(.borderless)
                .foregroundStyle(.green)
                .help(Text("Take over generated content", bundle: .module))
        }
    }
}

#Preview("Take Over Entry") {
    SheetEntryTakeOverButton(
        rootModel: .fake,
        parentModel: SheetButtonPreviewData.parent,
        entryModel: SheetButtonPreviewData.entry,
        onlyIcon: false
    )
    .padding()
}
