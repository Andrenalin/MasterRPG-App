// @copyright André Trettin

import CoreRPG

import PdfRPG
import SwiftUI

enum EditorRoute: Equatable, Hashable, Codable {
    case mapEditor(UUID)
    case quickEditor(UUID)
    case selectionPdf
    case linkSelection(ItemRowModel)
    case addLink(ItemRowModel)
}

extension EditorRoute: NavigationDestination {
    public var method: NavigationMethod {
        switch self {
        case .quickEditor, .mapEditor:
            return .managedCover
        case .addLink:
            return .managedSheet
        case .selectionPdf, .linkSelection:
            return .push
        }
    }

    public var body: some View {
        DestinationEditorRoute(route: self)
    }
}

struct DestinationEditorRoute: View {
    let route: EditorRoute
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .mapEditor(let itemId):
            RootEditCanvasMap(itemId: itemId)
        case .quickEditor(let itemId):
            QuickEntryEditor(model: root.itemController.itemOrEmpty(for: itemId))
                .environment(root.listDisplayModel)
        case .selectionPdf:
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.mapEditModel.selectionPdf)
        case .linkSelection(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedEntryId: itemRowModel.entryId, destinationModule: itemRowModel.typeId)
        case .addLink(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedModule: itemRowModel.typeId, selectedEntryId: root.editController.sheetEditorModel.entryId, destinationModule: root.editController.sheetEditorModel.module)
        }
    }
}
