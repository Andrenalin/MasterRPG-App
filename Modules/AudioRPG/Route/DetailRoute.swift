// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

enum DetailRoute: Equatable, Hashable, Codable {
    case detail(UUID)
    case selection(UUID)
}

extension DetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .detail(let id): "detail/\(id.uuidString)"
        case .selection(let id): "selection/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "detail": self = .detail(uuid)
        case "selection": self = .selection(uuid)
        default: return nil
        }
    }
}

extension DetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            RootDestinationView(itemId: itemId, isRootView: false)
        case .selection(let itemId):
            SelectionDestinationView(itemId: itemId)
        }
    }
}

struct SelectionDestinationView: View {
    let itemId: UUID
    
    var body: some View {
        SelectionListView(itemId: itemId)
    }
}
