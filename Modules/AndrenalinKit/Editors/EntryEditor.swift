// @copyright André Trettin

import SwiftUI

public struct EntryEditor<EditController: EntryDataEditable, Content: View, LinkAction: View, AddAction: View>: View {
    public init(editControllable: EditController, @ViewBuilder contentView: @escaping () -> Content, @ViewBuilder linkActionView: @escaping () -> LinkAction, @ViewBuilder addActionView: @escaping () -> AddAction) {
        self.editControllable = editControllable
        self.contentView = contentView
        self.linkActionView = linkActionView
        self.addActionView = addActionView
    }

    public init(editControllable: EditController, @ViewBuilder contentView: @escaping () -> Content, @ViewBuilder linkActionView: @escaping () -> LinkAction) where AddAction == EmptyView {
        self.editControllable = editControllable
        self.contentView = contentView
        self.linkActionView = linkActionView
        self.addActionView = { EmptyView() }
    }

    let editControllable: EditController
    let contentView: () -> Content
    let linkActionView: () -> LinkAction
    let addActionView: () -> AddAction

    @Environment(ListModel.self) private var itemListModel

    @State private var showDeleteAlert: Bool = false
    @State private var removeEntryList = RemoveEntryListModel()

    @State private var scrollId: UUID?
    
    public var body: some View {
        let _ = Self._printChanges()
        
        VStack {
            actionBarView

            ScrollViewReader { proxy in
                contentView()
                    .onChange(of: scrollId, initial: false) {
                        if let scrollId {
                            proxy.scrollTo(scrollId)
                            self.scrollId = nil
                        }
                    }
            }
#if os(macOS)
            .tableStyle(.bordered)
            .alternatingRowBackgrounds(.enabled)
            .onDeleteCommand {
                guard !editControllable.editorModel.selection.isEmpty else { return }
                Task {
                    await checkDeleteEntries(ids: editControllable.editorModel.selection, alwaysDeleteCheck: true)
                }
            }
            .onMoveCommand { direction in
                guard editControllable.editorModel.selected.count == 1 && (direction == .left || direction == .right) else { return }
                guard let entryId = editControllable.editorModel.selected.first else { return }
                editControllable.move(entryId: entryId, up: direction == .left)
            }
#endif
            .onChange(of: editControllable.editorModel.selected, initial: true) {
                withAnimation { syncSelection(with: editControllable.editorModel.selected) }
            }
            .onChange(of: editControllable.editorModel.selection, initial: true) {
                guard let entryId = editControllable.editorModel.selection.last else { return }
                withAnimation { editControllable.editorModel.currentEntryId = entryId }
            }
            .onChange(of: editControllable.editorModel.currentListItem, initial: true) {
                guard let entryId = editControllable.editorModel.currentListItem?.model.entryId, !editControllable.editorModel.selected.contains(entryId) else { return }
                withAnimation { editControllable.editorModel.selected = [entryId] }
            }
            .onChange(of: editControllable.editorModel.currentEntryId, initial: true) {
                guard let entryId = editControllable.editorModel.currentEntryId else { return }
                if editControllable.editorModel.expandedEntries[entryId, default: false] == false {
                    withAnimation {
                        editControllable.editorModel.expandedEntries = [:]
                        editControllable.editorModel.expandedEntries[entryId] = true
                    }
                }
            }
            .onChange(of: editControllable.editorModel.deleteAlertIds, initial: false) {
                guard !editControllable.editorModel.deleteAlertIds.isEmpty else { return }
                Task {
                    await checkDeleteEntries(ids: editControllable.editorModel.deleteAlertIds)
                }
            }
            .sheetFullScreen(isPresented: $showDeleteAlert) {
                EffectedLinkAction(itemControllable: editControllable.itemControllable, removeEntryList: removeEntryList) {
                    deleteSelectedEntries(rowModels: $0)
                }
            }
        }
    }
}

private extension EntryEditor {
    var model: EditController.Model {
        editControllable.model
    }

    func syncSelection(with newSelected: Set<UUID>) {
        let existingSelected = newSelected.filter { selectedId in
            editControllable.model.entries.contains { $0.id == selectedId }
        }
        var newSelection = editControllable.editorModel.selection.filter { existingSelected.contains($0) }
        var diffSelection = Array(existingSelected.filter { !newSelection.contains($0) })
        diffSelection.sort { a, b in
            guard let itemA = editControllable.model.entries.firstIndex(where: { $0.id == a }),
                  let itemB = editControllable.model.entries.firstIndex(where: { $0.id == b }) else { return false }
            return itemA < itemB
        }
        newSelection.append(contentsOf: diffSelection)
        editControllable.editorModel.selection <=> newSelection
        editControllable.editorModel.selected <=> existingSelected
    }

    var actionBarView: some View {
        HStack {
            Button {
                let newId = editControllable.addNewEntry()
                withAnimation {
                    editControllable.editorModel.expandedEntries = [newId: true]
                    scrollId = newId
                }
            } label: {
                Label { Text("Add", bundle: .module) } icon: { Image(systemName: "plus") }
            }

            addActionView()

            Text("\(editControllable.editEntries.count) Entry", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            linkActionView()
        }
    }

    func deleteSelectedEntries(rowModels: [ItemRowModel]) {
        editControllable.remove(entryIds: rowModels.compactMap { $0.entryId })
    }

    func checkDeleteEntries(ids: [UUID], alwaysDeleteCheck: Bool = false) async {
        removeEntryList.removeItems = ids.map { ItemRowModel(itemId: model.id, entryId: $0, typeId: editControllable.itemControllable.itemDataModel.networkModule) }
        if alwaysDeleteCheck {
            showDeleteAlert.toggle()
        } else {
            if editControllable.isUsed(rowModels: removeEntryList.removeItems) {
                showDeleteAlert.toggle()
            } else {
                deleteSelectedEntries(rowModels: removeEntryList.removeItems)
            }
        }
    }
}
