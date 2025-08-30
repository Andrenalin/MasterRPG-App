// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public enum ItemRootRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension ItemRootRoute: RawRepresentable {
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

extension ItemRootRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRootView(selectedId: itemId) {
            }
        }
    }
}
