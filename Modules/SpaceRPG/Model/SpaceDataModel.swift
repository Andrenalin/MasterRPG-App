// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class SpaceDataModel {
    init(
        id: UUID = UUID(),
        name: String = "",
        information: String = "",
        category: ItemListCategory = .building,
        tags: [String] = [],
        displayState: Int = 0,
        parentId: UUID? = nil,
        url: URL? = nil,
        entries: [SpaceEntryDataModel]? = nil
    ) {
        self.id = id
        self.name = name
        self.information = information
        self.category = category
        self.tags = tags
        self.displayState = displayState
        self.parentId = parentId
        self.url = url
        self.entries = entries
    }

    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    public var name: String = ""
    public var information: String = ""
    private var _nameLWW: CRDT<String> = CRDT(wrappedValue: "")
    private var _informationLWW: CRDT<String> = CRDT(wrappedValue: "")
    
    public var category: ItemListCategory = ItemListCategory.adventure
    public var tags: [String] = []
    public var displayState: Int = 0
    public var parentId: UUID? = nil
    public var url: URL?
    public var fileUrl: FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: SpaceDataModel.typeId.token)
    }
    
    @Relationship(deleteRule: .cascade) private var entries: [SpaceEntryDataModel]?
}

extension SpaceDataModel {
    public var entryModels: [SpaceEntryDataModel] {
        get {
            guard let all = entries else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = newValue
        }
    }

    func entryOrNew(for id: UUID) -> SpaceEntryDataModel {
        if let entry = entryModels.first(where: { $0.id == id }) {
            return entry
        }
        return SpaceEntryDataModel(id: id)
    }
    
    @MainActor public var specialCategory: Bool {
        category == .folder || category == SpaceDataModel.collectionCategory
    }
}

extension SpaceDataModel {
    public static func model(modelContext: ModelContext?, id: UUID?) -> SpaceDataModel? {
        guard let modelContext, let id else { return nil }
        let fetchDesc = FetchDescriptor<SpaceDataModel>()
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

extension SpaceDataModel: ImageFileLoadable {}
extension SpaceDataModel: ItemDataAccessable {
    public static var typeId: NetworkModules { .space }
    public subscript(id: UUID) -> SpaceEntryDataModel {
        get { entryModels.first(where: { $0.id == id }) ?? SpaceEntryDataModel(id: id) }
        set(newValue) {
            guard let index = entryModels.firstIndex(where: { $0.id == id }) else { return }
            entryModels[index] = newValue
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
    public func reset(entries: [SpaceEntryDataModel]) {
        self.entryModels = entries
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

extension SpaceDataModel: ListItemFolderable {
    public var isFolder: Bool {
        category == .folder
    }
    @MainActor public var subItems: ([SpaceDataModel], [UUID: UUID]) {
        guard specialCategory else { return ([], [:]) }
        var entryIds: [UUID: UUID] = [:]
        let items: [SpaceDataModel] = entryModels.compactMap {
            guard let childId = $0.childId, childId != id else { return nil }
            if let model = SpaceDataModel.model(modelContext: modelContext, id: childId), model.displayState == 0 {
                entryIds[childId] = $0.id
                return model
            }
            return nil
        }
        return (items, entryIds)
    }
    @MainActor public static let dropItem: SpaceDataModel = SpaceDataModel(id: UUID(), name: "3D Model", information: "Drop or select a 3D model", category: .drop)
    @MainActor public static var collectionCategory: ItemListCategory = .models
}

extension SpaceDataModel: ItemDataModelable {
    public typealias Model = SpaceDataModel
    public typealias ExchangeModel = SpaceModel
}

extension SpaceDataModel {
    public static var newItem: SpaceDataModel {
        SpaceDataModel(name: "", information: "", category: .building, tags: [])
    }
    
    public var itemModel: SpaceModel {
        let entries = entryModels.map { $0.entryModel }
        return SpaceModel(
            id: id,
            name: _nameLWW,
            description: _informationLWW,
            tags: CRDT(wrappedValue: tags),
            category: CRDT(wrappedValue: category),
            displayState: displayState,
            fileUrl: CRDTDataUpdate(wrappedValue: fileUrl),
            entries: CRDTDataUpdate(wrappedValue: entries)
        )
    }
}
