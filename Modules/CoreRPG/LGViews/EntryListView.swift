// @copyright André Trettin

import CoreExternalRPG
import Foundation
import SwiftUI

public struct EntryListView: View {
    public init(editController: any EntryDataEditable) {
        self.editController = editController
    }
    
    let editController: any EntryDataEditable
        
    @Namespace private var zoomNamespace
    
    public var body: some View {
        ForEach(editController.model.entries, id: \.id) { entry in
            EntryEditRow(editController: editController, entry: entry, cacheItemListModel: editController.cacheItemListModel)
                .modifier(ZoomDestinationViewModifier(sourceID: entry.id.uuidString, namespace: zoomNamespace))
                .contextMenu {
                    editButton(entry: entry)
                    Divider()
                    duplicateButton(entry: entry)
                    Divider()
                    removeButton(entry: entry)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading) {
                    editButton(entry: entry, onlyIcon: true)
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
    }
}

private extension EntryListView {
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
