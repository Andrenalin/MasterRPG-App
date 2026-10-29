// @copyright André Trettin

import SwiftUI

enum InternalRoute: Equatable, Codable {
    case export(ids: [UUID])
    case groupEditor(ids: [UUID])
    case removeAlert
    case batchExtraction(ids: [UUID])
    case convertGroup(source: ItemRowModel)
    case cloudFolderScan
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
            AffectedLinkActionPanelView(root: root)
        case .batchExtraction(let ids):
            root.viewControllable.batchExtractionView(
                itemController: root.itemControllable,
                editController: root.editControllable,
                ids: ids
            ) ?? AnyView(EmptyView())
        case .convertGroup(let source):
            // Snapshots its candidates on open; a different source needs fresh state.
            // See CODE_AUDIT_18 §8.5.
            SheetEntryConvertToGroupView(rootModel: root.editControllable.editorModel.sheetRootModel, source: source)
                .id(source)
        case .cloudFolderScan:
            CloudFolderScanView(root: root)
        }
    }
}

#Preview {
    InternalRouteDestinationView(route: .removeAlert)
        .environment(ItemRootController.fake)
}
