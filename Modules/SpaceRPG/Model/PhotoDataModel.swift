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
        degrees: Double = 0,
        url: URL? = nil,
        entries: [PhotoEntryDataModel] = []
    ) {
        self.id = id
        self.name = name
        self.information = information
        self.category = category
        self.tags = tags
        self.displayState = displayState
        self.degrees = degrees
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
    
    public var degrees: Double = 0
    var url: URL?
    var fileUrl: FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: "Photos")
    }
    
    @Relationship(deleteRule: .cascade) public var entries: [PhotoEntryDataModel]? = []
    
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
    static func model(modelContext: ModelContext, id: UUID?) -> PhotoDataModel? {
        guard let id else { return nil }
        let fetchDesc = FetchDescriptor<PhotoDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        return models?.first { $0.id == id }
    }

    func modelActor() -> PhotoDataModelActor? {
        guard let container = modelContext?.container else { return nil }
        return PhotoDataModelActor(modelContainer: container)
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

    var entriesModel: [PhotoEntryDataModel] {
        get {
            guard let all = entries else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = newValue
        }
    }

    func entryOrNew(for id: UUID) -> PhotoEntryDataModel {
        if let entry = entriesModel.first(where: { $0.id == id }) {
            return entry
        }
        return PhotoEntryDataModel(id: id)
    }
}

extension PhotoDataModel: ItemDataAccessable {
    public subscript(id: UUID) -> PhotoEntryDataModel {
        get {
            entriesModel.first(where: { $0.id == id }) ?? PhotoEntryDataModel(id: id)
        }
        set(newValue) {
            guard let index = entriesModel.firstIndex(where: { $0.id == id }) else { return }
            entriesModel[index] = newValue
        }
    }
    
    public typealias Entry = PhotoEntryDataModel
    
    public static var typeId: NetworkModules { .photo }
}

extension PhotoDataModel {
    var photoModel: PhotoModel {
        let entries = entriesModel.map { $0.photoEntryModel }
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
