// @copyright André Trettin

import SwiftUI

struct SheetContextMenuView: View {
    init(root: ItemRootController, entryEditable: any EntryDataEditable, model: TableSheetModel, entry: SheetModel) {
        self.root = root
        self.entryEditable = entryEditable
        self.model = model
        self.entry = entry
    }
    
    let root: ItemRootController
    let entryEditable: any EntryDataEditable
    let model: TableSheetModel
    let entry: SheetModel
    
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        Divider()
        moveIntoButton(entryEditable: entryEditable, groups: model.groupFolders(entryDataEditable: entryEditable, entry: entry))
        moveOutOfGroupButton(entryEditable: entryEditable)

        moveUpButton
        moveDownButton
        Divider()
        duplicateButton
#if os(iOS)
        linkButton
#endif
        Divider()
    }
}

private extension SheetContextMenuView {
    var duplicateButton: some View {
        Button {
            guard let entryId = entry.source.entryId, let newId = entryEditable.copy(itemId: entry.source.itemId, entryId: entryId) else { return }

            withAnimation {
                model.add(entryId: newId)
                model.setCurrentItem(source: entry.source, entryId: newId)
                model.updateParent()
            }
        } label: {
            Label {
                Text("Duplicate \(entry.name.withoutLink())", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("d", modifiers: .shift)
#endif
    }
    
    var linkButton: some View {
        Button {
            guard let entryId = entry.source.entryId else { return }
            navigator.navigate(to: entryEditable.linkSelectionDestination(itemRowModel: ItemRowModel(itemId: entry.source.itemId, entryId: entryId, typeId: entry.source.typeId)), method: .managedSheet)
        } label: {
            Label {
                Text("Add Links", bundle: .module)
            } icon: {
                Image(systemName: "link.badge.plus")
            }
        }
    }

    @ViewBuilder func moveIntoButton(entryEditable: any EntryDataEditable, groups: [FolderRepresentable]) -> some View {
        if !groups.isEmpty {
            Menu {
                ForEach(groups) { folder in
                    Button {
                        model.move(entryDataEditable: entryEditable, entry: entry, into: folder)
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
                    Text("Move \(entry.name.withoutLink()) into", bundle: .module)
                } icon: {
                    Image(systemName: "list.bullet.indent")
                }
            }
        }
    }

    @ViewBuilder func moveOutOfGroupButton(entryEditable: any EntryDataEditable) -> some View {
        if let parent = model.parentGroup(entryDataEditable: entryEditable) {
            Button {
                model.moveOutOfGroup(entryDataEditable: entryEditable, entry: entry, parent: parent)
            } label: {
                Label {
                    Text("Move \(entry.name.withoutLink()) out to \(parent.name)", bundle: .module)
                } icon: {
                    Image(systemName: "list.bullet")
                }
            }
        }
    }

    var moveUpButton: some View {
        Button {
            guard let currentIndex = model.sheetModel.entries.firstIndex(where: { $0.id == entry.id }), currentIndex > 0 else { return }
            withAnimation {
                model.move(entryDataEditable: entryEditable, indexSet: IndexSet(integer: currentIndex), to: currentIndex - 1)
            }
        } label: {
            Label {
                Text("Move Up", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up")
            }
        }
        .disabled(model.sheetModel.entries.first?.id == entry.id)
#if !os(tvOS)
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
#endif
    }

    var moveDownButton: some View {
        Button {
            guard let currentIndex = model.sheetModel.entries.firstIndex(where: { $0.id == entry.id }), currentIndex < model.sheetModel.entries.count - 1 else { return }
            withAnimation {
                model.move(entryDataEditable: entryEditable, indexSet: IndexSet(integer: currentIndex), to: currentIndex + 2)
            }
        } label: {
            Label {
                Text("Move Down", bundle: .module)
            } icon: {
                Image(systemName: "arrow.down")
            }
        }
        .disabled(model.sheetModel.entries.last?.id == entry.id)
#if !os(tvOS)
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
#endif
    }
}
