// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

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
            DetailRouteDestinationView(itemId: itemId, isSubFolder: false)
                .navigationDestination(DiceDetailRoute.self)
                .navigationAutoReceive(DiceDetailRoute.self)
        }
    }
}

extension DiceRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        DiceRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    let isSubFolder: Bool
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        DetailRootView(root: root, editController: root.editController, model: root.itemController.itemOrEmpty(for: itemId), isSubFolder: isSubFolder)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}


public enum DiceDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
}

extension DiceDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
        default: return nil
        }
    }
}

extension DiceDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            DetailRouteDestinationView(itemId: itemId, isSubFolder: true)
        }
    }
}

extension DiceDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        DiceDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
        }
    }
}
