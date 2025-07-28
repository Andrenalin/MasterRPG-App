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
        url: URL? = nil,
        entries: [SpaceEntryDataModel]? = nil
    ) {
        self.id = id
        self.name = name
        self.information = information
        self.category = category
        self.tags = tags
        self.displayState = displayState
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
    
    var url: URL?
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
}

extension SpaceDataModel {
    func reset(name: String) {
        _nameLWW.wrappedValue = name
        self.name = name
    }
    
    func reset(information: String) {
        _informationLWW.wrappedValue = information
        self.information = information
    }
}

extension SpaceDataModel {
    static func model(modelContext: ModelContext, id: UUID?) -> SpaceDataModel? {
        guard let id else { return nil }
        let fetchDesc = FetchDescriptor<SpaceDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        return models?.first { $0.id == id }
    }

    func modelActor() -> DataModelActor? {
        guard let container = modelContext?.container else { return nil }
        return DataModelActor(modelContainer: container)
    }

    func withTransaction(_ transaction: () -> Void) {
        if let modelContext {
            do {
                try modelContext.transaction {
                    transaction()
                }
            } catch {
                modelContext.rollback()
            }
        } else {
            transaction()
        }
    }
}

extension SpaceDataModel: HasPhotoModel {}
extension SpaceDataModel: ItemDataAccessable {
    public static var typeId: NetworkModules { .space }

    public subscript(id: UUID) -> SpaceEntryDataModel {
        get {
            entryModels.first(where: { $0.id == id }) ?? SpaceEntryDataModel(id: id)
        }
        set(newValue) {
            guard let index = entryModels.firstIndex(where: { $0.id == id }) else { return }
            entryModels[index] = newValue
        }
    }
}

extension SpaceDataModel {
    static var newItem: SpaceDataModel {
        SpaceDataModel(name: "", information: "", category: .building, tags: [])
    }
    
    var spaceModel: SpaceModel {
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
