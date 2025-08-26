// @copyright André Trettin

import Foundation
import SwiftData

@Model
public final class ItemDataModel {
    public init(
        id: UUID = UUID(),
        module: NetworkModules = .audio,
        name: String = "",
        information: String = "",
        category: ItemListCategory = .all,
        tags: [String] = [],
        url: URL? = nil,
        displayState: Int = 0,
        parentId: UUID? = nil,
        entries: [EntryDataModel] = []
    ) {
        self.id = id
        self.module = module

        self.name = name
        self.information = information

        self.category = category
        self.tags = tags
        self.url = url

        self.displayState = displayState
        self.parentId = parentId

        self.entries_ = entries
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    public var module: NetworkModules = NetworkModules.audio

    public var name: String = ""
    public var information: String = ""

    public var category: ItemListCategory = ItemListCategory.all
    public var tags: [String] = []
    public var url: URL?

    public var displayState: Int = 0
    public var parentId: UUID? = nil

    private(set) var _nameLWW: CRDT<String> = CRDT(wrappedValue: "")
    private(set) var _informationLWW: CRDT<String> = CRDT(wrappedValue: "")

    @Relationship(deleteRule: .cascade) private var entries_: [EntryDataModel]? = []
}

public extension ItemDataModel {
    var entries: [EntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }

    var fileUrl: FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: module.token)
    }

    var isFolder: Bool {
        category == .folder
    }

    var specialCategory: Bool {
        category == .folder || category.isCollection
    }
}

extension ItemDataModel {
    public subscript(id: UUID) -> EntryDataModel {
        get { entries.first(where: { $0.id == id }) ?? EntryDataModel.empty(id: id) }
        set(newValue) {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }
    public func reset(name: String) {
        _nameLWW.wrappedValue = name
        self.name = name
    }
    public func reset(category: ItemListCategory) {
        self.category = category
    }
    public func reset(displayState: Int) {
        self.displayState = displayState
    }
    public func reset(entries: [EntryDataModel]) {
        self.entries = entries
    }
    public func reset(information: String) {
        _informationLWW.wrappedValue = information
        self.information = information
    }
    public func reset(tags: [String]) {
        self.tags = tags
    }
    public func reset(url: URL?) {
        self.url = url
    }
}

public extension ItemDataModel {
    static func model(modelContext: ModelContext?, id: UUID?) -> ItemDataModel? {
        guard let modelContext, let id else { return nil }
        let fetchDesc = FetchDescriptor<ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        return models?.first { $0.id == id }
    }

    func modelActor() -> DataModelActor? {
        guard let container = modelContext?.container else { return nil }
        return DataModelActor(modelContainer: container)
    }

    func withTransaction(_ transaction: (ModelContext) -> Void) {
        if let modelContext {
            do {
                try modelContext.transaction {
                    transaction(modelContext)
                }
            } catch {
                modelContext.rollback()
            }
        }
    }
}

extension ItemDataModel {
    public var subItems: ([ItemDataModel], [UUID: UUID]) {
        guard specialCategory else { return ([], [:]) }
        var entryIds: [UUID: UUID] = [:]
        let items: [ItemDataModel] = entries.compactMap {
            guard $0.childId != id else { return nil }
            if let model = ItemDataModel.model(modelContext: modelContext, id: $0.childId), model.displayState == 0 {
                entryIds[$0.childId] = $0.id
                return model
            }
            return nil
        }
        return (items, entryIds)
    }
}

extension ItemDataModel {
    public static var newItem: ItemDataModel {
        ItemDataModel(name: "", information: "", category: .music, tags: [])
    }
}

public extension ItemDataModel {
    func urlAdr(linkNumber: Int) -> String {
        "\(URL.appScheme)://\(module.token)/\(linkNumber)/\(id)"
    }
    
    func urlAdr(linkNumber: Int, entryId: UUID) -> String {
        "\(urlAdr(linkNumber: linkNumber))/\(entryId)"
    }
    
    func urlName() -> String {
        name.withoutLink()
    }
    
    func urlName(entryId: UUID) -> String {
        self[entryId].name.withoutLink()
    }
    
    func url(linkNumber: Int) -> String {
        "[\(urlName())](\(urlAdr(linkNumber: linkNumber)))"
    }
    
    func url(linkNumber: Int, entryId: UUID) -> String {
        "[\(urlName(entryId: entryId))](\(urlAdr(linkNumber: linkNumber, entryId: entryId)))"
    }
}
