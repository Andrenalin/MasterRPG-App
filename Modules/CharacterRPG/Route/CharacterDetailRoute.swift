// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

public enum CharacterDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
#if !os(tvOS)
    case characterExtraction(UUID)
#endif
}

extension CharacterDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        case .folderInline(let id): "folderInline/\(id.uuidString)"
#if !os(tvOS)
        case .characterExtraction(let id): "characterExtraction/\(id.uuidString)"
#endif
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
        case "folderInline": self = .folderInline(uuid)
#if !os(tvOS)
        case "characterExtraction": self = .characterExtraction(uuid)
#endif
        default: return nil
        }
    }
}

extension CharacterDetailRoute: NavigationDestination {
    public var body: some View {
        CharacterDetailRouteDestinationView(route: self)
    }
}

extension CharacterDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        CharacterDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        CharacterDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
#if !os(tvOS)
            case .characterExtraction(let id): return id
#endif
        }
    }
}

struct CharacterDetailRouteDestinationView: View {
    let route: CharacterDetailRoute

    @Environment(CharacterRootModel.self) private var root

    var body: some View {
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
        case .characterExtraction(let itemId):
            CharacterExtractionDestination(itemId: itemId)
#endif
        }
    }
}

#Preview(traits: .mockData) {
    CharacterDetailRouteDestinationView(route: .folder(ValueModel.previewId))
}
