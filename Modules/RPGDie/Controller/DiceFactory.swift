// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftData
import SwiftUI

public enum DiceFactory {
    @MainActor public static var sharedRoot: DiceRoot?
    
    @MainActor
    public static func root(container: ModelContainer) -> DiceRoot {
        let root = DiceRoot(container: container)
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
            .navigationAutoReceive(DiceRoute.self)
    }
    
    @MainActor @ViewBuilder public static func detailView(root: DiceRoot) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(DiceRoot.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            DiceRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .dice)
        }
    }
}


public enum DiceRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension DiceRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .detail(let id): "detail/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "detail": self = .detail(uuid)
        default: return nil
        }
    }
}

extension DiceRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(DiceRoot.self) private var root
    
    var body: some View {
        RootExtendedDetail(itemRowTreeModel: ItemRowTreeModel(itemId: itemId, typeId: .dice), tabId: KnownRoutes.mainTabId)
        //DetailRootView(selectedId: itemId)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            //.environment(root.rootController)
    }
}
