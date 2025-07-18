// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

public enum TableRoute: Hashable, Codable {
    case detail(ItemRowTreeModel?, UUID)
}

extension TableRoute: NavigationDestination {
    public var body: some View {
        switch self {
            case .detail(let itemRowTreeModel, let tabId):
                if let itemRowTreeModel {
                    RootExtendedDetail(itemRowTreeModel: itemRowTreeModel, tabId: tabId)
                } else {
                    SplitContentUnavailable(module: .table)
                }
        }
    }
}
