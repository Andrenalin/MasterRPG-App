// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryListView<LinkType: LinkDataTransferable>: View {
    public init(editController: any EntryDataEditable, linkTypes: LinkType.Type, headerTitle: LocalizedStringKey) {
        self.editController = editController
        self.linkTypes = linkTypes
        self.headerTitle = headerTitle
    }
    
    let editController: any EntryDataEditable
    let linkTypes: LinkType.Type
    let headerTitle: LocalizedStringKey
    
    @Environment(\.navigator) private var navigator
    @Namespace private var zoomNamespace
    
    public var body: some View {
        Section {
            ForEach(editController.model.entries, id: \.id) { entry in
                EntryEditRow(editController: editController, entry: entry, cacheItemListModel: editController.cacheItemListModel)
                    .id(entry.id)
                    .dropDestination(for: linkTypes, isEnabled: true) { items, sessions in
                        items.forEach {
                            editController.add(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, destinationEntryId: entry.id)
                        }
                    }
                    .modifier(ZoomDestinationViewModifier(sourceID: entry.id.uuidString, namespace: zoomNamespace))
                    .contextMenu {
                        editButton(entry: entry)
                        Divider()
                        duplicateButton(entry: entry)
                        linkButton(entry: entry)
                        Divider()
                        removeButton(entry: entry)
                    }
#if !os(tvOS)
                    .swipeActions(edge: .leading) {
                        editButton(entry: entry, onlyIcon: true)
                        linkButton(entry: entry, onlyIcon: true)
                    }
#endif
            }
            .onDelete { indexSet in
                editController.remove(entryIndexSet: indexSet)
            }
            .onMove { indexSet, index in
                editController.move(entryFrom: indexSet, to: index)
            }
            .onAppear {
                editController.editorModel.zoomNamespaceId = zoomNamespace
            }
        } header: {
            Text(headerTitle)
        }
        .toolbar {
            toolbarContent
        }
    }
}

private extension EntryListView {
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            Button {
                withAnimation {
                    let entryId = editController.addNewEntry()
                    editController.editorModel.currentEntryId = entryId
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.25))
                        editController.editorModel.scrollEntryId = entryId
                    }
                }
            } label: {
                Label {
                    Text("Add new Entry", bundle: .module)
                } icon: {
                    Image(systemName: "note.text.badge.plus")
                }
            }
        }
    }
    
    func editButton(entry: any EntryDataAccessable, onlyIcon: Bool = false) -> some View {
        Button {
            withAnimation { editController.editorModel.currentEntryId = entry.id }
        } label: {
            if onlyIcon {
                Image(systemName: "pencil")
            } else {
                Label {
                    Text("Edit \(entry.name)", bundle: .module)
                } icon: {
                    Image(systemName: "pencil")
                }
            }
        }
    }
    
    func duplicateButton(entry: any EntryDataAccessable) -> some View {
        Button {
            withAnimation {
                let newId = editController.copy(entryId: entry.id, shouldSave: true)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.25))
                    editController.editorModel.currentEntryId = newId
                    try? await Task.sleep(for: .seconds(0.25))
                    editController.editorModel.scrollEntryId = newId
                }
            }
        } label: {
            Label {
                Text("Duplicate \(entry.name)", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
    }
    
    func linkButton(entry: any EntryDataAccessable, onlyIcon: Bool = false) -> some View {
        Button {
            navigator.navigate(to: editController.linkSelectionDestination(for: entry.id), method: .managedSheet)
        } label: {
            if onlyIcon {
                Image(systemName: "link.badge.plus")
            } else {
                Label {
                    Text("Add Links", bundle: .module)
                } icon: {
                    Image(systemName: "link.badge.plus")
                }
            }
        }
    }
    
    func removeButton(entry: any EntryDataAccessable) -> some View {
        Button(role: .destructive) {
            withAnimation {
                editController.remove(entryId: entry.id)
            }
        } label: {
            Label {
                Text("Delete \(entry.name)", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }
}
