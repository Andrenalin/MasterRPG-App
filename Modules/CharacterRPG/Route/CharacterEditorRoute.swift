// @copyright André Trettin

import CoreRPG

import PdfRPG
import SwiftUI

enum CharacterEditorRoute: Equatable, Hashable, Codable {
    case quickEditor(UUID)
    case selectionPdf
    case linkSelection(ItemRowModel)
    case addLink(ItemRowModel)
}

extension CharacterEditorRoute: NavigationDestination {
    public var method: NavigationMethod {
        switch self {
        case .quickEditor:
            return .managedCover
        case .addLink:
            return .managedSheet
        case .selectionPdf, .linkSelection:
            return .push
        }
    }

    public var body: some View {
        DestinationCharacterEditorRouteView(route: self)
    }
}

struct DestinationCharacterEditorRouteView: View {
    let route: CharacterEditorRoute
    
    @Environment(CharacterRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .quickEditor(let itemId):
            QuickEntryEditor(model: root.itemController.itemOrEmpty(for: itemId))
        case .selectionPdf:
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.valueEditModel.selectionPdf)
        case .linkSelection(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedEntryId: itemRowModel.entryId, destinationModule: itemRowModel.typeId)
        case .addLink(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedModule: itemRowModel.typeId, selectedEntryId: root.editController.sheetEditorModel.entryId, destinationModule: root.editController.sheetEditorModel.module)
        }
    }
}
