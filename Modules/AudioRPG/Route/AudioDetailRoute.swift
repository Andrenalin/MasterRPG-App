// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum AudioDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
}

extension AudioDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        case .folderInline(let id): "folderInline/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
        case "folderInline": self = .folder(uuid)
        default: return nil
        }
    }
}

extension AudioDetailRoute: NavigationDestination {
    public var body: some View {
        AuduioDetailRoutelDestinationView(route: self)
    }
}

extension AudioDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        AudioDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
        }
    }
}

struct AuduioDetailRoutelDestinationView: View {
    let route: AudioDetailRoute

    @Environment(AudioRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .folder(let itemId):
            DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
                .environment(root.listDisplayModel)
                .environment(root.searchModel)
                .environment(root.rootController)

        case .folderInline(let itemId):
            DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
        }
    }
}
