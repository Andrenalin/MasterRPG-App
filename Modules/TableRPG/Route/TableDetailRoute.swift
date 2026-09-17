// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

enum TableDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
#if !os(tvOS)
    case tableExtraction(UUID)
#endif
}

extension TableDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): TaggedIdRoute.rawValue(token: "folder", id: id)
        case .folderInline(let id): TaggedIdRoute.rawValue(token: "folderInline", id: id)
#if !os(tvOS)
        case .tableExtraction(let id): TaggedIdRoute.rawValue(token: "tableExtraction", id: id)
#endif
        }
    }

    public init?(rawValue: String) {
        guard let route = TaggedIdRoute.parse(rawValue, resolve: { token, id -> Self? in
            switch token {
            case "folder": return .folder(id)
            case "folderInline": return .folderInline(id)
#if !os(tvOS)
            case "tableExtraction": return .tableExtraction(id)
#endif
            default: return nil
            }
        }) else { return nil }
        self = route
    }
}

extension TableDetailRoute: NavigationDestination {
    public var body: some View {
        TableDetailRouteDestinationView(route: self)
    }
}

extension TableDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        TableDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        TableDetailRoute.folder(detail)
    }

    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
#if !os(tvOS)
            case .tableExtraction(let id): return id
#endif
        }
    }
}

struct TableDetailRouteDestinationView: View {
    let route: TableDetailRoute

    @Environment(TableRootModel.self) private var root

    var body: some View {
        switch route {
        case .folder(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailListView(root: root, model: model, folderListController: root.folderListController.copy(listModel: FolderListModel(parentModel: parentModel, navigationModel: root.navigationModel)))
            }
        case .folderInline(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailFolderListView(root: root, model: model, folderListController: root.folderListController.copy(listModel: FolderListModel(parentModel: parentModel, navigationModel: root.navigationModel)), isSubFolder: true)
            }

#if !os(tvOS)
        case .tableExtraction(let itemId):
            TableExtractionDestination(itemId: itemId)
#endif
        }
    }
}

#Preview(traits: .mockData) {
    TableDetailRouteDestinationView(route: .folder(TableModel.previewId))
}
