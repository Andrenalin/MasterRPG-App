// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public struct EntryListView<Controller: EntryEditControllable>: View {
    public init(entryEditController: Controller, model: Controller.EditDataModel) {
        self.entryEditController = entryEditController
        self.model = model
    }
    
    let entryEditController: Controller
    let model: Controller.EditDataModel
        
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Namespace private var zoomNamespace
    
    public var body: some View {
        ForEach(model.entries) { entry in
            EntryRow(entryId: entry.entryId, name: entry.name, content: entry.content, cacheItemListModel: cacheItemListModel)
                .modifier(ZoomDestinationViewModifier(sourceID: entry.entryId.uuidString, namespace: zoomNamespace))
                .contextMenu {
                    duplicateButton(entry: entry)
                        .resetAppColorScheme()
                }
                .swipeActions(edge: .leading) {
                    editButton(id: entry.entryId)
                }
        }
        .onDelete { indexSet in
            entryEditController.remove(indexSet, from: model)
        }
        .onMove { indexSet, index in
            entryEditController.move(indexSet, index: index, from: model)
        }
        .onAppear {
            entryEditController.editorModel.zoomNamespaceId = zoomNamespace
        }
    }
}

private extension EntryListView {
    func editButton(id: UUID) -> some View {
        Button {
            withAnimation { entryEditController.editorModel.currentEntryId = id }
        } label: {
            Image(systemName: "pencil")
        }
    }
    
    func duplicateButton(entry: Controller.EditDataModel.DataModel) -> some View {
        Button {
            withAnimation {
                let newId = entryEditController.duplicate(entry: entry, in: model)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.25))
                    entryEditController.editorModel.currentEntryId = newId
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


}
