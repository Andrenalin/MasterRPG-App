// @copyright André Trettin

import SwiftUI

struct SheetEntryEditButton: View {
    let rootModel: SheetRootModel
    let entryModel: SheetModel
    let isEditor: Bool
    let onlyIcon: Bool

    var body: some View {
        Button {
            withAnimation {
                entryModel.isEditing.toggle()
                if isEditor {
                    rootModel.editorModel.setEdit(source: entryModel.source)
                }
            }
        } label: {
            Label {
                Text("Edit \(entryModel.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "square.and.pencil")
                    .opacity(0)
                    .imageScale(.large)
                    .overlay {
                        Image(systemName: entryModel.isEditing ? "square.and.pencil" : "pencil")
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
}

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
        .borderLessTVBottonStyle()
        .keyboardShortcutAll("r", modifiers: .shift)
    }
}

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
