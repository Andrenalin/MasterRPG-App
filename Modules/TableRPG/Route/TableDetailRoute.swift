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
        case .folder(let id): "folder/\(id.uuidString)"
        case .folderInline(let id): "folderInline/\(id.uuidString)"
#if !os(tvOS)
        case .tableExtraction(let id): "tableExtraction/\(id.uuidString)"
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
        case "tableExtraction": self = .tableExtraction(uuid)
#endif
        default: return nil
        }
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

#if !os(tvOS)
private struct TableExtractionDestination: View {
    let itemId: UUID

    @Environment(TableRootModel.self) private var root

    var body: some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        if model.entries.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Entries", bundle: .module)
                } icon: {
                    Image(systemName: "tablecells.badge.ellipsis")
                }
            } description: {
                Text("This table has no entries to analyze.", bundle: .module)
            }
        } else {
            TextSummaryExtractionView(module: .table, entriesText: formatEntries(model)) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection)
            }
        }
    }

    private func formatEntries(_ model: TableModel) -> String {
        var lines: [String] = []
        if !model.name.isEmpty {
            lines.append("Table: \(model.name)")
            lines.append("")
        }
        for entry in model.entries {
            lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }
}
#endif
