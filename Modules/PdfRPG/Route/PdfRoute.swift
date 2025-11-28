// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

public enum PdfRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension PdfRoute: RawRepresentable {
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

extension PdfRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId, isSubFolder: false)
                .navigationDestination(PdfDetailRoute.self)
                .navigationAutoReceive(PdfDetailRoute.self)
        }
    }
}

extension PdfRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        PdfRoute.detail(detail)
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
    @Environment(PdfRootModel.self) private var root
    
    var body: some View {
        DetailRootView(root: root, editController: root.editController, model: root.itemController.itemOrEmpty(for: itemId), isSubFolder: isSubFolder)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}

public enum PdfDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
}

extension PdfDetailRoute: RawRepresentable {
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

extension PdfDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            DetailRouteDestinationView(itemId: itemId, isSubFolder: true)
        }
    }
}

extension PdfDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        PdfDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
        }
    }
}
