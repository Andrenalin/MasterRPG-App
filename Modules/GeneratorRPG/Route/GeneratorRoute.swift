// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftData
import SwiftUI

public enum GeneratorRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension GeneratorRoute: RawRepresentable {
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

extension GeneratorRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        GeneratorRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

extension GeneratorRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId, isSubFolder: false)
                .navigationDestination(GeneratorDetailRoute.self)
                .navigationAutoReceive(GeneratorDetailRoute.self)
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    let isSubFolder: Bool
    @Environment(GeneratorRootModel.self) private var root
    
    var body: some View {
        DetailRootView(root: root, editController: root.editController, model: root.itemController.itemOrEmpty(for: itemId), isSubFolder: isSubFolder)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}

public enum GeneratorDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
}

extension GeneratorDetailRoute: RawRepresentable {
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

extension GeneratorDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            DetailRouteDestinationView(itemId: itemId, isSubFolder: true)
        }
    }
}

extension GeneratorDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        GeneratorDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
        }
    }
}
