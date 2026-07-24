// @copyright André Trettin

import CoreRPG
import SwiftUI

enum RuleDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
}

extension RuleDetailRoute: RawRepresentable {
    var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        case .folderInline(let id): "folderInline/\(id.uuidString)"
        }
    }

    init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first,
              let value = values.last,
              let id = UUID(uuidString: String(value)) else { return nil }
        switch token {
        case "folder": self = .folder(id)
        case "folderInline": self = .folderInline(id)
        default: return nil
        }
    }
}

extension RuleDetailRoute: NavigationDestination {
    var body: some View {
        RuleDetailRouteDestinationView(route: self)
    }
}

extension RuleDetailRoute: ItemDetailRoute {
    static func detailRoute(itemId: UUID) -> RuleDetailRoute { .folder(itemId) }
    func reset(detail: UUID) -> RuleDetailRoute { .folder(detail) }

    func detail() -> UUID? {
        switch self {
        case .folder(let id), .folderInline(let id): id
        }
    }
}

private struct RuleDetailRouteDestinationView: View {
    let route: RuleDetailRoute
    @Environment(RuleRootModel.self) private var root

    var body: some View {
        switch route {
        case .folder(let itemId):
            if let model = root.itemController.itemSync(for: itemId),
               let parentId = model.parentId,
               let parent = root.itemController.itemSync(for: parentId) {
                DetailListView(
                    root: root,
                    model: model,
                    folderListController: root.folderListController.copy(
                        listModel: FolderListModel(
                            parentModel: parent,
                            navigationModel: root.navigationModel
                        )
                    )
                )
            }
        case .folderInline(let itemId):
            if let model = root.itemController.itemSync(for: itemId),
               let parentId = model.parentId,
               let parent = root.itemController.itemSync(for: parentId) {
                DetailFolderListView(
                    root: root,
                    model: model,
                    folderListController: root.folderListController.copy(
                        listModel: FolderListModel(
                            parentModel: parent,
                            navigationModel: root.navigationModel
                        )
                    ),
                    isSubFolder: true
                )
            }
        }
    }
}

#Preview("Rule folder route", traits: .mockData) {
    RuleDetailRoute.folder(RuleModel.previewChildID).body
}

#Preview("Rule inline folder route", traits: .mockData) {
    RuleDetailRoute.folderInline(RuleModel.previewChildID).body
}
