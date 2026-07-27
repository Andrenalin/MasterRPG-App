// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import SwiftUI

public enum TableEditorRoute: Equatable, Hashable, Codable {
    case quickEditor(UUID)
    case selectionPdf
    case linkSelection(ItemRowModel)
    case addLink(ItemRowModel)
}

extension TableEditorRoute: NavigationDestination {
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
        DestinationTableEditorRouteView(route: self)
    }
}

struct DestinationTableEditorRouteView: View {
    let route: TableEditorRoute

    @Environment(TableRootModel.self) private var root

    var body: some View {
        switch route {
        case .quickEditor(let itemId):
            QuickEntryEditor(model: root.itemController.itemOrEmpty(for: itemId))
        case .selectionPdf:
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.tableEditModel.selectionPdf)
        case .linkSelection(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedEntryId: itemRowModel.entryId, destinationModule: itemRowModel.typeId)
        case .addLink(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedModule: itemRowModel.typeId, selectedEntryId: root.editController.editorModel.sheetEditorModel.entryId, destinationModule: root.editController.editorModel.sheetEditorModel.module)
        }
    }
}

#Preview(traits: .mockData) {
    DestinationTableEditorRouteView(route: .quickEditor(TableModel.previewId))
}
