// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class AudioDataModel {
    init(
        id: UUID = UUID(),
        name: String = "",
        information: String = "",
        category: ItemListCategory = .music,
        tags: [String] = [],
        displayState: Int = 0,
        degrees: Double = 0,
        url: URL? = nil,
        entries: [AudioEntryDataModel] = []
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
    public var fileUrl: FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: "Photos")
    }
    
    @Relationship(deleteRule: .cascade) private var entries: [AudioEntryDataModel]? = []
}

extension AudioDataModel {
    public var entryModels: [AudioEntryDataModel] {
        get {
            guard let all = entries else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = newValue
        }
    }

    func entryOrNew(for id: UUID) -> AudioEntryDataModel {
        if let entry = entryModels.first(where: { $0.id == id }) {
            return entry
        }
        return AudioEntryDataModel(id: id)
    }
}

extension AudioDataModel {
    func reset(name: String) {
        _nameLWW.wrappedValue = name
        self.name = name
    }
    
    func reset(information: String) {
        _informationLWW.wrappedValue = information
        self.information = information
    }
}

extension AudioDataModel {
    static func model(modelContext: ModelContext, id: UUID?) -> AudioDataModel? {
        guard let id else { return nil }
        let fetchDesc = FetchDescriptor<AudioDataModel>()
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

extension AudioDataModel: HasPhotoModel {}
extension AudioDataModel: ItemDataAccessable {
    public static var typeId: NetworkModules { .audio }

    public subscript(id: UUID) -> AudioEntryDataModel {
        get {
            entryModels.first(where: { $0.id == id }) ?? AudioEntryDataModel(id: id)
        }
        set(newValue) {
            guard let index = entryModels.firstIndex(where: { $0.id == id }) else { return }
            entryModels[index] = newValue
        }
    }
}

extension AudioDataModel {
    var photoModel: AudioModel {
        let entries = entryModels.map { $0.photoEntryModel }
        return AudioModel(
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
