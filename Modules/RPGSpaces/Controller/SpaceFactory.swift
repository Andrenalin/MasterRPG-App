// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftData
import SwiftUI

public enum SpaceFactory {
    @MainActor
    public static func root(container: ModelContainer) -> SpaceRoot {
        SpaceRoot(container: container)
    }

    @MainActor
    public static func rootView(for root: SpaceRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    public static func rootView(isTabbed: Bool = false) -> some View {
        SpaceRootView(isTabbed: isTabbed)
    }

    @MainActor
    public static func rootExtendedView(for root: SpaceRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
}

public enum SpaceRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension SpaceRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .space)
                }
        }
    }
}
