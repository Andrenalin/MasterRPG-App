// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

public enum AudioDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
}

extension AudioDetailRoute: RawRepresentable {
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

extension AudioDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            AuduioDetailRoutelDestinationView(itemId: itemId)
        }
    }
}

extension AudioDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        AudioDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
        }
    }
}

struct AuduioDetailRoutelDestinationView: View {
    let itemId: UUID

    @Environment(AudioRootModel.self) private var root
    
    var body: some View {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.folderListController.detailInspectorModel)
            .environment(root.rootController)
    }
}
