// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class DiceDataModel {
    init(
        id: UUID = UUID(),
        name: String = "",
        information: String = "",
        category: ItemListCategory = .rules,
        tags: [String] = [],
        displayState: Int = 0,
        parentId: UUID? = nil,
        url: URL? = nil,
        entries: [DiceEntryDataModel] = [],
        config: DiceConfigDataModel? = nil
    ) {
        self.id = id
        self.name = name
        self.information = information
        self.category = category
        self.tags = tags
        self.displayState = displayState
        self.parentId = parentId
        self.url = url
        self.entries_ = entries
        self.config_ = config
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    public var name: String = ""
    public var information: String = ""
    private var _nameLWW: CRDT<String> = CRDT(wrappedValue: "")
    private var _informationLWW: CRDT<String> = CRDT(wrappedValue: "")
    
    public var category: ItemListCategory = ItemListCategory.rules
    public var tags: [String] = []
    public var displayState: Int = 0
    public var parentId: UUID? = nil
    public var url: URL?
    public var fileUrl: FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: DiceDataModel.typeId.token)
    }

    @Relationship(deleteRule: .cascade) private var entries_: [DiceEntryDataModel]? = []
    @Relationship(deleteRule: .cascade) private var config_: DiceConfigDataModel? = nil
}

extension DiceDataModel {
    public var entries: [DiceEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }

    func entryOrNew(for id: UUID) -> DiceEntryDataModel {
        if let entry = entries.first(where: { $0.id == id }) {
            return entry
        }
        return DiceEntryDataModel(id: id)
    }
    
    public var config: DiceConfigDataModel {
        get { config_ ?? DiceConfigDataModel.twenty }
        set { config_ = newValue }
    }

    @MainActor public var specialCategory: Bool {
        category == .folder || category == DiceDataModel.collectionCategory
    }
}

extension DiceDataModel {
    public static func model(modelContext: ModelContext?, id: UUID?) -> DiceDataModel? {
        guard let modelContext, let id else { return nil }
        let fetchDesc = FetchDescriptor<DiceDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        return models?.first { $0.id == id }
    }

    func modelActor() -> DataModelActor? {
        guard let container = modelContext?.container else { return nil }
        return DataModelActor(modelContainer: container)
    }

    public func withTransaction(_ transaction: (ModelContext) -> Void) {
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

extension DiceDataModel: ItemDataAccessable {
    public static var typeId: NetworkModules { .dice }
    public subscript(id: UUID) -> DiceEntryDataModel {
        get { entries.first(where: { $0.id == id }) ?? DiceEntryDataModel(id: id) }
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
    public func reset(entries: [DiceEntryDataModel]) {
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

extension DiceDataModel: ListItemFolderable {
    public var isFolder: Bool {
        category == .folder
    }
    @MainActor public var subItems: ([DiceDataModel], [UUID: UUID]) {
        guard specialCategory else { return ([], [:]) }
        var entryIds: [UUID: UUID] = [:]
        let items: [DiceDataModel] = entries.compactMap {
            guard let childId = $0.childId, childId != id else { return nil }
            if let model = DiceDataModel.model(modelContext: modelContext, id: childId), model.displayState == 0 {
                entryIds[childId] = $0.id
                return model
            }
            return nil
        }
        return (items, entryIds)
    }
    @MainActor public static let dropItem: DiceDataModel = DiceDataModel(id: UUID(), name: "Dice", information: "Drop or select a dice", category: .drop)
    @MainActor public static var collectionCategory: ItemListCategory = .diceBag
}

extension DiceDataModel: ItemDataModelable {
    public typealias Model = DiceDataModel
    public typealias ExchangeModel = DiceModel
}

extension DiceDataModel {
    public static var newItem: DiceDataModel {
        DiceDataModel(name: "", information: "", category: .rules, tags: [])
    }
    
    public var itemModel: DiceModel {
        let entries = entries.map { $0.entryModel }
        return DiceModel(
            id: id,
            name: _nameLWW,
            description: _informationLWW,
            tags: CRDT(wrappedValue: tags),
            category: CRDT(wrappedValue: category),
            displayState: displayState,
            degrees: CRDT(wrappedValue: 0),
            fileUrl: CRDTDataUpdate(wrappedValue: fileUrl),
            entries: CRDTDataUpdate(wrappedValue: entries)
        )
    }
}
