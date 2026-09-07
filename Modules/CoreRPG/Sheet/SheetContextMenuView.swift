// @copyright André Trettin

import SwiftUI

struct SheetContextMenuView: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool

    var body: some View {
        if isEditor {
            SheetEntryQuickEditButton(rootModel: rootModel, entryModel: entryModel, parentModel: parentModel, onlyIcon: false)
            Divider()
            SheetEntryAddButton(rootModel: rootModel, parentModel: parentModel, onlyIcon: false)
            SheetContextMenuAddGroupButton(rootModel: rootModel, parentModel: parentModel)
            SheetContextMenuConvertToGroupButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel)
        }
        Divider()
        SheetContextMenuMoveIntoButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel)
        SheetContextMenuMoveOutOfGroupButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel)
        SheetContextMenuMoveUpButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel)
        SheetContextMenuMoveDownButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel)
        Divider()
        SheetContextMenuDuplicateButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel)
#if os(iOS)
        if isEditor {
            SheetContextMenuLinkButton(rootModel: rootModel, entryModel: entryModel)
        }
#endif
        Divider()
    }
}

#Preview("Entry Menu") {
    SheetContextMenuView(rootModel: .fake, parentModel: SheetModel.empty, entryModel: SheetModel.empty, isEditor: true)
        .padding()
}

// MARK: - Extracted subviews (CODE_AUDIT §8.2)

private struct SheetContextMenuAddGroupButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel

    var body: some View {
        if let editable = rootModel.entryDataEditable(for: parentModel.source), editable.canAddGroups {
            SheetEntryAddGroupButton(rootModel: rootModel, parentModel: parentModel, onlyIcon: false)
        }
    }
}

private struct SheetContextMenuConvertToGroupButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel

    var body: some View {
#if !os(tvOS)
        if entryModel.source.entryId != nil, let editable = rootModel.entryDataEditable(for: entryModel.source), editable.canConvertGroups {
            SheetEntryConvertToGroupButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
        }
#endif
    }
}

private struct SheetContextMenuDuplicateButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel

    var body: some View {
        Button {
            withAnimation {
                rootModel.duplicateEntry(entryModel: entryModel, in: parentModel)
            }
        } label: {
            Label {
                Text("Duplicate \(entryModel.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
        .keyboardShortcutAll("d", modifiers: .shift)
    }
}

private struct SheetContextMenuLinkButton: View {
    let rootModel: SheetRootModel
    let entryModel: SheetModel

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            guard let entryId = entryModel.source.entryId,
                  let editable = rootModel.entryDataEditable(for: entryModel.source) else { return }
            navigator.navigate(to: editable.linkSelectionDestination(itemRowModel: ItemRowModel(itemId: entryModel.source.itemId, entryId: entryId, typeId: entryModel.source.typeId)), method: .managedSheet)
        } label: {
            Label {
                Text("Add Links", bundle: .module)
            } icon: {
                Image(systemName: "link.badge.plus")
            }
        }
    }
}

private struct SheetContextMenuMoveIntoButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel

    var body: some View {
        let groups = rootModel.groupFolders(for: entryModel)
        if !groups.isEmpty {
            Menu {
                ForEach(groups) { folder in
                    Button {
                        rootModel.moveEntry(entryModel, in: parentModel, into: folder)
                    } label: {
                        Label {
                            Text(folder.name)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                }
            } label: {
                Label {
                    Text("Move \(entryModel.name.withoutLink()) into", bundle: .module)
                } icon: {
                    Image(systemName: "list.bullet.indent")
                }
            }
        }
    }
}

private struct SheetContextMenuMoveOutOfGroupButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel

    var body: some View {
        if let parent = rootModel.parentGroup(for: entryModel) {
            Button {
                rootModel.moveEntryOutOfGroup(entryModel, in: parentModel, parent: parent)
            } label: {
                Label {
                    Text("Move \(entryModel.name.withoutLink()) out to \(parent.name)", bundle: .module)
                } icon: {
                    Image(systemName: "list.bullet")
                }
            }
            // Some modules' parentFolder(itemId:) can resolve through an
            // unrelated hierarchy (e.g. CharacterRPG falling back to a
            // library folder for a root-level value entry) — disabled rather
            // than hidden there, since the entry can't actually move outside
            // its character.
            .disabled(!rootModel.canMoveOutOfGroup(for: entryModel))
        }
    }
}

private struct SheetContextMenuMoveUpButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel

    var body: some View {
        Button {
            withAnimation {
                rootModel.moveEntry(entryModel: entryModel, in: parentModel, up: true)
            }
        } label: {
            Label {
                Text("Move Up", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up")
            }
        }
        .disabled(parentModel.entries.first?.id == entryModel.id)
        .keyboardShortcutAll(.upArrow, modifiers: [.command, .option])
    }
}

private struct SheetContextMenuMoveDownButton: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel

    var body: some View {
        Button {
            withAnimation {
                rootModel.moveEntry(entryModel: entryModel, in: parentModel, up: false)
            }
        } label: {
            Label {
                Text("Move Down", bundle: .module)
            } icon: {
                Image(systemName: "arrow.down")
            }
        }
        .disabled(parentModel.entries.last?.id == entryModel.id)
        .keyboardShortcutAll(.downArrow, modifiers: [.command, .option])
    }
}
