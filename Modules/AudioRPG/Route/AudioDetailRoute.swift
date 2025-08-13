// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

public enum AudioDetailRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension AudioDetailRoute: RawRepresentable {
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

extension AudioDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            AudioDetailDestinationView(itemId: itemId)
        }
    }
}

struct AudioDetailDestinationView: View {
    let itemId: UUID
    
    @Environment(AudioRootModel.self) private var root
    var body: some View {
        if itemId == AudioDataModel.dropItem.id {
            SelectionRootListView()
                .environment(root.searchModel)
        } else {
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}
