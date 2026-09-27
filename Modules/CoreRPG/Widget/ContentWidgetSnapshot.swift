// @copyright André Trettin

#if !os(tvOS)
import Foundation
import WidgetKit

public enum ContentWidgetKind {
    public static let characters = "CharacterContentWidget"
    public static let adventures = "AdventureContentWidget"
}

public struct ContentWidgetItem: Codable, Equatable, Identifiable, Sendable {
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    public let id: UUID
    public let name: String
}

public struct ContentWidgetSnapshot: Codable, Equatable, Sendable {
    public init(module: NetworkModules, totalCount: Int, items: [ContentWidgetItem]) {
        self.module = module
        self.totalCount = totalCount
        self.items = items
    }

    public let module: NetworkModules
    public let totalCount: Int
    public let items: [ContentWidgetItem]

    public static func load(for module: NetworkModules) -> Self {
        guard let data = UserDefaults.appGroupDefaults?
            .data(forKey: storageKey(for: module)),
              let snapshot = try? JSONCoding.decoder.decode(Self.self, from: data) else {
            return Self(module: module, totalCount: 0, items: [])
        }
        return snapshot
    }

    @MainActor
    public static func publish(module: NetworkModules, from dataModel: ItemDataModel) {
        let visibleItems = dataModel.items.compactMap { itemId -> ContentWidgetItem? in
            guard let item = dataModel.itemData[itemId] as? any ItemDataAccessable,
                  item.displayState == DisplayStateMask.fullVisible.rawValue,
                  !item.specialCategory,
                  !item.name.isEmpty else { return nil }
            return ContentWidgetItem(id: item.id, name: item.name)
        }
        let snapshot = Self(
            module: module,
            totalCount: visibleItems.count,
            items: Array(visibleItems.prefix(4))
        )
        guard let data = try? JSONCoding.encoder.encode(snapshot) else { return }
        UserDefaults.appGroupDefaults?
            .set(data, forKey: storageKey(for: module))
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind(for: module))
    }

    public var rootURL: URL? {
        URL(string: "\(URL.appScheme)://\(module.token)")
    }

    public func itemURL(for item: ContentWidgetItem) -> URL? {
        URL(string: "\(URL.appScheme)://\(module.token)/1/\(item.id)")
    }

    private static func storageKey(for module: NetworkModules) -> String {
        switch module {
        case .value: "characterWidgetSnapshot"
        case .adventure: "adventureWidgetSnapshot"
        default: "contentWidgetSnapshot.\(module.token)"
        }
    }

    private static func widgetKind(for module: NetworkModules) -> String {
        switch module {
        case .value: ContentWidgetKind.characters
        case .adventure: ContentWidgetKind.adventures
        default: "ContentWidget.\(module.token)"
        }
    }
}
#endif
