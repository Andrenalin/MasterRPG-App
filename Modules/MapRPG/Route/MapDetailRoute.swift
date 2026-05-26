// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

public enum MapDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
#if !os(tvOS)
    case mapExtraction(UUID)
#endif
}

extension MapDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        case .folderInline(let id): "folderInline/\(id.uuidString)"
#if !os(tvOS)
        case .mapExtraction(let id): "mapExtraction/\(id.uuidString)"
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
        case "mapExtraction": self = .mapExtraction(uuid)
#endif
        default: return nil
        }
    }
}

extension MapDetailRoute: NavigationDestination {
    public var body: some View {
        MapDetailRouteDestinationView(route: self)
    }
}

extension MapDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        MapDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        MapDetailRoute.folder(detail)
    }

    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
#if !os(tvOS)
            case .mapExtraction(let id): return id
#endif
        }
    }
}

struct MapDetailRouteDestinationView: View {
    let route: MapDetailRoute

    @Environment(MapRootModel.self) private var root

    var body: some View {
        switch route {
        case .folder(let itemId):
            DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))

        case .folderInline(let itemId):
            DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))

#if !os(tvOS)
        case .mapExtraction(let itemId):
            MapExtractionDestination(itemId: itemId)
#endif
        }
    }
}

#if !os(tvOS)
private struct MapExtractionDestination: View {
    let itemId: UUID

    @Environment(MapRootModel.self) private var root

    var body: some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        let visibleEntries = model.entries.filter { !$0.isHexGrid }
        if visibleEntries.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Rooms", bundle: .module)
                } icon: {
                    Image(systemName: "mappin.slash")
                }
            } description: {
                Text("This map has no rooms to analyze.", bundle: .module)
            }
        } else {
            TextSummaryExtractionView(module: .map, entriesText: formatEntries(model, entries: visibleEntries)) { content, selection in
                root.editController.applyExtractedContent(content, to: itemId, selection: selection)
            }
        }
    }

    private func formatEntries(_ model: MapModel, entries: [MapEntryModel]) -> String {
        var lines: [String] = []
        if !model.name.isEmpty {
            lines.append("Map: \(model.name)")
            lines.append("")
        }
        for entry in entries {
            lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }
}
#endif
