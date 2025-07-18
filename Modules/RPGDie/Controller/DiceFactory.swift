// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import CoreData
import SwiftUI

public enum DiceFactory {
    @MainActor public static var sharedRoot: DiceRoot?
    
    @MainActor
    public static func root(for context: NSManagedObjectContext) -> DiceRoot {
        let root = DiceRoot(context: context)
        if sharedRoot == nil {
            sharedRoot = root
        }
        return root
    }

    @MainActor
    public static func rootView(for root: DiceRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }

    public static func diceImage(for die: RawDie, result: Int) -> Image {
        let model = DieModel(id: UUID(), die: die)
        return model.diceImage(for: result)
    }
    
    @MainActor
    public static func rootExtendedView(for root: DiceRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
}

public enum DiceRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension DiceRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .dice)
                }
        }
    }
}
