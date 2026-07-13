// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import PdfRPG
import SwiftUI

enum MapEditorRoute: Equatable, Hashable, Codable {
    case mapEditor(UUID)
    case mapTileEditor(UUID)
    case quickEditor(UUID)
    case selectionPdf
    case linkSelection(ItemRowModel)
    case addLink(ItemRowModel)
    case generator(UUID)
}

extension MapEditorRoute: NavigationDestination {
    public var method: NavigationMethod {
        switch self {
        case .quickEditor, .mapEditor, .mapTileEditor:
            return .managedCover
        case .addLink, .generator:
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
#if !os(tvOS)
    @Environment(GeneratorRootModel.self) private var generatorRoot
#endif

    var body: some View {
        switch route {
        case .mapEditor(let itemId):
            RootEditCanvasMap(itemId: itemId)
        case .mapTileEditor(let itemId):
            RootEditCanvasMap(itemId: itemId, isTileEditor: true)
        case .quickEditor(let itemId):
            QuickEntryEditor(model: root.itemController.itemOrEmpty(for: itemId))

        case .selectionPdf:
            root.pdfRoot.viewController.linkListView(type: .selection, itemSelectionModel: root.editController.mapEditModel.selectionPdf)
        case .linkSelection(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedEntryId: itemRowModel.entryId, destinationModule: itemRowModel.typeId)
        case .addLink(let itemRowModel):
            EditorLinkView(root: root.rootController, model: root.itemController.itemOrEmpty(for: itemRowModel.itemId), editorLinkModel: root.editorLinkModel, selectedModule: itemRowModel.typeId, selectedEntryId: root.editController.editorModel.sheetEditorModel.entryId, destinationModule: root.editController.editorModel.sheetEditorModel.module)
        case .generator(let itemId):
#if os(tvOS)
            EmptyView()
                .id(itemId)
#else
            if let rootManager = root.rootManager {
                let sheetModel = root.sheetController.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: true)
                generatorRoot.viewController.inlineChat(root: generatorRoot, sheetModel: sheetModel)
            }
#endif
        }
    }
}

#Preview(traits: .mockData) { DestinationMapEditorRoute(route: .quickEditor(MapModel.previewId)) }
