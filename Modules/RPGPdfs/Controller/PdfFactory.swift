// @copyright André Trettin

import AndrenalinKit
import CoreData
import SwiftUI

public enum PdfFactory {
    @MainActor
    public static func root(for context: NSManagedObjectContext) -> PdfRoot {
        PdfRoot(context: context)
    }

    @MainActor
    public static func rootView(for root: PdfRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: PdfRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
}

public enum PdfRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension PdfRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .pdf)
                }
        }
    }
}
