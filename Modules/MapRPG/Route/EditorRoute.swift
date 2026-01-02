// @copyright André Trettin

import CoreRPG

import PdfRPG
import SwiftUI

enum EditorRoute: Equatable, Hashable, Codable {
    case mapEditor
    case quickEditor(UUID)
    case selectionPdf
    case linkSelection(ItemRowModel)
    case addLink(ItemRowModel)
}

extension EditorRoute: NavigationDestination {
    public var body: some View {
        DestinationEditorRoute(route: self)
    }
}

struct DestinationEditorRoute: View {
    let route: EditorRoute
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .mapEditor:
            MapEditWindow(editController: root.editController)
        case .quickEditor(let itemId):
            QuickEntryEditor(model: root.itemController.itemOrEmpty(for: itemId))
        case .selectionPdf:
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.mapEditModel.selectionPdf)
        case .linkSelection(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedEntryId: itemRowModel.entryId)
        case .addLink(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedModule: itemRowModel.typeId, selectedEntryId: root.editController.editorModel.currentEntryId)
        }
    }
}
