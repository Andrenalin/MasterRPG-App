// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class PhotoDataModel {
    init(
        id: UUID = UUID(),
        name: String = "",
        information: String = "",
        category: ItemListCategory = .adventure,
        tags: [String] = [],
        displayState: Int = 0,
        parentId: UUID? = nil,
        url: URL? = nil,
        entries: [PhotoEntryDataModel] = [],
        degrees: Double = 0
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
        self.degrees = degrees
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
    var url: URL?
    public var fileUrl: FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: PhotoDataModel.typeId.token)
    }
    
    public var degrees: Double = 0

    @Relationship(deleteRule: .cascade) private var entries: [PhotoEntryDataModel]? = []
}

extension PhotoDataModel {
    public var entryModels: [PhotoEntryDataModel] {
        get {
            guard let all = entries else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = newValue
        }
    }

    func entryOrNew(for id: UUID) -> PhotoEntryDataModel {
        if let entry = entryModels.first(where: { $0.id == id }) {
            return entry
        }
        return PhotoEntryDataModel(id: id)
    }
    
    var specialCategory: Bool {
        category == .folder || category == .collection
    }
}

extension PhotoDataModel {
    func reset(name: String) {
        _nameLWW.wrappedValue = name
        self.name = name
    }
    
    func reset(information: String) {
        _informationLWW.wrappedValue = information
        self.information = information
    }
}

extension PhotoDataModel {
    static func model(modelContext: ModelContext?, id: UUID?) -> PhotoDataModel? {
        guard let modelContext, let id else { return nil }
        let fetchDesc = FetchDescriptor<PhotoDataModel>()
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

extension PhotoDataModel: HasPhotoModel {}
extension PhotoDataModel: ItemDataAccessable {
    public static var typeId: NetworkModules { .photo }

    public subscript(id: UUID) -> PhotoEntryDataModel {
        get {
            entryModels.first(where: { $0.id == id }) ?? PhotoEntryDataModel(id: id)
        }
        set(newValue) {
            guard let index = entryModels.firstIndex(where: { $0.id == id }) else { return }
            entryModels[index] = newValue
        }
    }
}

extension PhotoDataModel: ListItemFolderable {
    public var isFolder: Bool {
        category == .folder
    }
    public var subItems: [PhotoDataModel] {
        guard isFolder else { return [] }
        return entryModels.compactMap { PhotoDataModel.model(modelContext: modelContext, id: $0.itemId) }
    }
}


extension PhotoDataModel {
    static var newItem: PhotoDataModel {
        PhotoDataModel(name: "", information: "", category: .adventure, tags: [])
    }
    
    var itemModel: PhotoModel {
        let entries = entryModels.map { $0.entryModel }
        return PhotoModel(
            id: id,
            name: _nameLWW,
            description: _informationLWW,
            tags: CRDT(wrappedValue: tags),
            category: CRDT(wrappedValue: category),
            displayState: displayState,
            degrees: CRDT(wrappedValue: degrees),
            fileUrl: CRDTDataUpdate(wrappedValue: fileUrl),
            entries: CRDTDataUpdate(wrappedValue: entries)
        )
    }
}
