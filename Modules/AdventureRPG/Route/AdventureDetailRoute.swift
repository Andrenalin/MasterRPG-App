// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum AdventureDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
#if !os(tvOS)
    case adventureExtraction(UUID)
#endif
}

extension AdventureDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): TaggedIdRoute.rawValue(token: "folder", id: id)
        case .folderInline(let id): TaggedIdRoute.rawValue(token: "folderInline", id: id)
#if !os(tvOS)
        case .adventureExtraction(let id): TaggedIdRoute.rawValue(token: "adventureExtraction", id: id)
#endif
        }
    }

    public init?(rawValue: String) {
        guard let route = TaggedIdRoute.parse(rawValue, resolve: { token, id -> Self? in
            switch token {
            case "folder": return .folder(id)
            case "folderInline": return .folderInline(id)
#if !os(tvOS)
            case "adventureExtraction": return .adventureExtraction(id)
#endif
            default: return nil
            }
        }) else { return nil }
        self = route
    }
}

extension AdventureDetailRoute: NavigationDestination {
    public var body: some View {
        DestinationDetailAdventureRouteView(route: self)
    }
}

extension AdventureDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        AdventureDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        AdventureDetailRoute.folder(detail)
    }

    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
#if !os(tvOS)
            case .adventureExtraction(let id): return id
#endif
        }
    }
}

struct DestinationDetailAdventureRouteView: View {
    let route: AdventureDetailRoute

    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        switch route {
        case .folder(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailFolderControllerReader(listController: root.folderListController, itemId: itemId, parentModel: parentModel, navigationModel: root.navigationModel) { folderListController in
                    DetailListView(root: root, model: model, folderListController: folderListController)
                }
            }
        case .folderInline(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailFolderControllerReader(listController: root.folderListController, itemId: itemId, parentModel: parentModel, navigationModel: root.navigationModel) { folderListController in
                    DetailFolderListView(root: root, model: model, folderListController: folderListController, isSubFolder: true)
                }
            }

#if !os(tvOS)
        case .adventureExtraction(let itemId):
            AdventureExtractionDestination(itemId: itemId)
#endif
        }
    }
}

#Preview(traits: .mockData) { DestinationDetailAdventureRouteView(route: .folder(AdventureModel.previewId)) }
