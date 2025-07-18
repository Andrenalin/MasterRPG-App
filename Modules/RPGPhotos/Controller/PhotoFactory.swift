// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import CoreData
import SwiftUI

public enum PhotoFactory {
    @MainActor
    public static func root(for context: NSManagedObjectContext) -> PhotoRoot {
        PhotoRoot(context: context)
    }

    @MainActor
    public static func rootView(for root: PhotoRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: PhotoRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
}

public enum PhotoRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension PhotoRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .photo)
                }
        }
    }
}

