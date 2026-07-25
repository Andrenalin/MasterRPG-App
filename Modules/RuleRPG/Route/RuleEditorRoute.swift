// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum RuleEditorRoute: Equatable, Hashable, Codable {
    case quickEditor(UUID)
    case linkSelection(ItemRowModel)
    case addLink(ItemRowModel)
}

extension RuleEditorRoute: NavigationDestination {
    public var method: NavigationMethod {
        switch self {
        case .quickEditor: .managedCover
        case .linkSelection: .push
        case .addLink: .managedSheet
        }
    }

    public var body: some View {
        RuleEditorRouteDestinationView(route: self)
    }
}

private struct RuleEditorRouteDestinationView: View {
    let route: RuleEditorRoute
    @Environment(RuleRootModel.self) private var root

    var body: some View {
        switch route {
        case .quickEditor(let itemId):
            RuleQuickEntryEditor(model: root.itemController.itemOrEmpty(for: itemId))
        case .linkSelection(let itemRowModel):
            EditorLinkView(
                root: root.rootController,
                model: root.itemController.itemOrEmpty(for: itemRowModel.itemId),
                editorLinkModel: root.editorLinkModel,
                selectedEntryId: itemRowModel.entryId,
                destinationModule: itemRowModel.typeId
            )
        case .addLink(let itemRowModel):
            EditorLinkView(
                root: root.rootController,
                model: root.itemController.itemOrEmpty(for: itemRowModel.itemId),
                editorLinkModel: root.editorLinkModel,
                selectedModule: itemRowModel.typeId,
                selectedEntryId: root.editController.editorModel.sheetEditorModel.entryId,
                destinationModule: root.editController.editorModel.sheetEditorModel.module
            )
        }
    }
}

#Preview("Rule quick editor route", traits: .mockData) {
    RuleEditorRoute.quickEditor(RuleModel.previewID).body
}
