// @copyright André Trettin

import SwiftUI

enum InternalRoute: Equatable, Codable {
    case export(ids: [UUID])
    case groupEditor(ids: [UUID])
    case removeAlert
    case batchExtraction(ids: [UUID])
}

extension InternalRoute: NavigationDestination {
    var body: some View {
        InternalRouteDestinationView(route: self)
    }
}

struct InternalRouteDestinationView: View {
    let route: InternalRoute
    
    @Environment(ItemRootController.self) private var root
    
    var body: some View {
        switch route {
        case .export(let ids):
            ExportProgressPanelView(exportController: root.exportControllable) {
                root.exportControllable.exporting(ids: Set(ids))
            }
            .presentationDetents([.height(160)])
        case .groupEditor(let ids):
            GroupEditorView(groupEditorController: GroupEditorController(itemController: root.itemControllable, editController: root.editControllable, ids: ids))
                .presentationDetents([.medium])
        case .removeAlert:
            EffectedLinkActionPanelView(root: root)
        case .batchExtraction(let ids):
            root.viewControllable.batchExtractionView(
                itemController: root.itemControllable,
                editController: root.editControllable,
                ids: ids
            ) ?? AnyView(EmptyView())
        }
    }
}
