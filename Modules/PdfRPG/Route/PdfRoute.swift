// @copyright André Trettin

import CoreRPG

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
            DestinationPdfRouteView(itemId: itemId)
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

struct DestinationPdfRouteView: View {
    let itemId: UUID

    @Environment(PdfRootModel.self) private var root
    
    var body: some View {
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootView(root: root, model: model)
                .environment(root.listDisplayModel)
                .environment(root.searchModel)
                .environment(root.rootController)
        }
    }
}
