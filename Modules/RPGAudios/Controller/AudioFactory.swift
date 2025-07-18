// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import CoreData
import SwiftUI

public enum AudioFactory {
    @MainActor
    public static func root(for context: NSManagedObjectContext) -> AudioRoot {
        AudioRoot(context: context)
    }

    @MainActor
    public static func rootView(for root: AudioRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }

    @MainActor
    public static func rootExtendedView(for root: AudioRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
}

public enum AudioRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension AudioRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .audio)
                }
        }
    }
}
