// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum RuleRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension RuleRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .detail(let id): "detail/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard values.first == "detail",
              let value = values.last,
              let id = UUID(uuidString: String(value)) else { return nil }
        self = .detail(id)
    }
}

extension RuleRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            RuleRouteDestinationView(itemId: itemId)
                .navigationAutoReceive(RuleDetailRoute.self)
        }
    }
}

extension RuleRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> RuleRoute { .detail(itemId) }

    public func reset(detail: UUID) -> RuleRoute { .detail(detail) }

    public func detail() -> UUID? {
        switch self {
        case .detail(let id): id
        }
    }
}

private struct RuleRouteDestinationView: View {
    let itemId: UUID
    @Environment(RuleRootModel.self) private var root

    var body: some View {
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootView(root: root, model: model)
        }
    }
}

#Preview("Rule detail route", traits: .mockData) {
    ManagedNavigationStack {
        RuleRoute.detail(RuleModel.previewId).body
    }
}
