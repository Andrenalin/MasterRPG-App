// @copyright André Trettin

import CoreRPG

import PdfRPG
import SwiftUI

enum MapEditorRoute: Equatable, Hashable, Codable {
    case mapEditor(UUID)
    case tileEditor(UUID)
    case quickEditor(UUID)
    case selectionPdf
    case linkSelection(ItemRowModel)
    case addLink(ItemRowModel)
}

extension MapEditorRoute: NavigationDestination {
    public var method: NavigationMethod {
        switch self {
        case .quickEditor, .mapEditor, .tileEditor:
            return .managedCover
        case .addLink:
            return .managedSheet
        case .selectionPdf, .linkSelection:
            return .push
        }
    }

    public var body: some View {
        DestinationMapEditorRoute(route: self)
    }
}

struct DestinationMapEditorRoute: View {
    let route: MapEditorRoute
    
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .mapEditor(let itemId):
            RootEditCanvasMap(itemId: itemId)
        case .tileEditor(let itemId):
            RootEditCanvasMap(itemId: itemId, isTileEditor: true)
        case .quickEditor(let itemId):
            QuickEntryEditor(model: root.itemController.itemOrEmpty(for: itemId))

        case .selectionPdf:
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.mapEditModel.selectionPdf)
        case .linkSelection(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedEntryId: itemRowModel.entryId, destinationModule: itemRowModel.typeId)
        case .addLink(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedModule: itemRowModel.typeId, selectedEntryId: root.editController.sheetEditorModel.entryId, destinationModule: root.editController.sheetEditorModel.module)
        }
    }
}
