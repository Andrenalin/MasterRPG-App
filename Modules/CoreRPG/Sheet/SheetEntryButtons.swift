// @copyright André Trettin

import SwiftUI

struct SheetEntryEditButton: View {
    let rootModel: SheetRootModel
    let entryModel: SheetModel
    let parentModel: SheetModel
    let isEditor: Bool
    let onlyIcon: Bool

    var body: some View {
        Button {
            withAnimation {
                if isEditor {
                    rootModel.setSelected(entryModel, parent: parentModel)
                    entryModel.isEditing.toggle()
                    rootModel.editorModel.setEdit(source: entryModel.source)
                } else {
                    rootModel.toggleInlineEditing(entryModel, parent: parentModel)
                }
            }
        } label: {
            Label {
                Text("Edit \(entryModel.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "square.and.pencil")
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .imageScale(.large)
                    .overlay {
                        Image(systemName: isEditing ? "square.and.pencil" : "pencil")
                            .imageScale(.large)
                            .foregroundStyle(.tint, .foreground, .tint)
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    }
            }
            .applyIf(onlyIcon) {
                $0.labelStyle(.iconOnly)
            }
        }
        .borderLessTVBottonStyle()
        .keyboardShortcutAll("e", modifiers: .shift)
    }

    private var isEditing: Bool {
        entryModel.isEditing
    }
}

@MainActor enum SheetButtonPreviewData {
    static let parent = SheetModel(
        source: ItemRowModel(itemId: .fixture1, typeId: .none),
        name: "Character",
        description: "Preview item",
        entries: []
    )
    static let entry = SheetModel(
        source: ItemRowModel(itemId: parent.source.itemId, entryId: .fixture2, typeId: .none),
        name: "Background",
        description: "A wandering ranger.",
        entries: []
    )
}

#Preview("Edit Entry") {
    SheetEntryEditButton(
        rootModel: .fake,
        entryModel: SheetButtonPreviewData.entry,
        parentModel: SheetButtonPreviewData.parent,
        isEditor: true,
        onlyIcon: false
    )
    .padding()
}
