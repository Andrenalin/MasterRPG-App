// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
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
        case .folder(let id): "folder/\(id.uuidString)"
        case .folderInline(let id): "folderInline/\(id.uuidString)"
#if !os(tvOS)
        case .adventureExtraction(let id): "adventureExtraction/\(id.uuidString)"
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
        case "adventureExtraction": self = .adventureExtraction(uuid)
#endif
        default: return nil
        }
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
                DetailListView(root: root, model: model, folderListController: root.folderListController.copy(listModel: FolderListModel(parentModel: parentModel, navigationModel: root.navigationModel)))
            }
        case .folderInline(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailFolderListView(root: root, model: model, folderListController: root.folderListController.copy(listModel: FolderListModel(parentModel: parentModel, navigationModel: root.navigationModel)), isSubFolder: true)
            }

#if !os(tvOS)
        case .adventureExtraction(let itemId):
            AdventureExtractionDestination(itemId: itemId)
#endif
        }
    }
}

#Preview(traits: .mockData) { DestinationDetailAdventureRouteView(route: .folder(AdventureModel.previewId)) }

#if !os(tvOS)
private struct AdventureExtractionDestination: View {
    let itemId: UUID

    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        if model.entries.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Entries", bundle: .module)
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
            } description: {
                Text("This adventure has no entries to analyze.", bundle: .module)
            }
        } else {
            TextSummaryExtractionView(module: .adventure, entriesText: formatEntries(model)) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection)
            }
        }
    }

    private func formatEntries(_ model: AdventureModel) -> String {
        var lines: [String] = []
        if !model.name.isEmpty {
            lines.append("Adventure: \(model.name)")
            lines.append("")
        }
        for entry in model.entries {
            lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }
}

#Preview(traits: .mockData) { AdventureExtractionDestination(itemId: AdventureModel.previewId) }
#endif
