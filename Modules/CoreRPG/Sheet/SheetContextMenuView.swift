// @copyright André Trettin

import SwiftUI

struct SheetContextMenuView: View {
    let rootModel: SheetRootModel
    let parentModel: SheetModel
    let entryModel: SheetModel
    let isEditor: Bool

    @Environment(\.navigator) private var navigator

    var body: some View {
        if isEditor {
            SheetEntryQuickEditButton(rootModel: rootModel, entryModel: entryModel, parentModel: parentModel, onlyIcon: false)
            Divider()
            SheetEntryAddButton(rootModel: rootModel, parentModel: parentModel, onlyIcon: false)
            addGroupButton
            convertToGroupButton
        }
        Divider()
        moveIntoButton
        moveOutOfGroupButton
        moveUpButton
        moveDownButton
        Divider()
        duplicateButton
#if os(iOS)
        if isEditor {
            linkButton
        }
#endif
        Divider()
    }
}

#Preview("Entry Menu") {
    SheetContextMenuView(rootModel: .fake, parentModel: SheetModel.empty, entryModel: SheetModel.empty, isEditor: true)
        .padding()
}

private extension SheetContextMenuView {
    @ViewBuilder var addGroupButton: some View {
        if let editable = rootModel.entryDataEditable(for: parentModel.source), editable.canAddGroups {
            SheetEntryAddGroupButton(rootModel: rootModel, parentModel: parentModel, onlyIcon: false)
        }
    }

    @ViewBuilder var convertToGroupButton: some View {
#if !os(tvOS)
        if entryModel.source.entryId != nil, let editable = rootModel.entryDataEditable(for: entryModel.source), editable.canConvertGroups {
            SheetEntryConvertToGroupButton(rootModel: rootModel, parentModel: parentModel, entryModel: entryModel, onlyIcon: false)
        }
#endif
    }

    var duplicateButton: some View {
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

    var linkButton: some View {
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

    @ViewBuilder var moveIntoButton: some View {
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

    @ViewBuilder var moveOutOfGroupButton: some View {
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

    var moveUpButton: some View {
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

    var moveDownButton: some View {
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
