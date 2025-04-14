// @copyright André Trettin

import AndrenalinKit
import SwiftUI

public enum AdventureRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension AdventureRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .adventure)
                }
        }
    }
}
