// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

enum DetailRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension DetailRoute: RawRepresentable {
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

extension DetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailDestinationView(itemId: itemId)
        }
    }
}

struct DetailDestinationView: View {
    let itemId: UUID
    
    @Environment(DiceRootModel.self) private var root
    var body: some View {
//        if itemId == DiceDataModel.dropItem.id {
//            SelectionRootView()
//                .environment(root.searchModel)
//        } else {
            RootDestinationView(itemId: itemId, isRootView: false)
//        }
    }
}
