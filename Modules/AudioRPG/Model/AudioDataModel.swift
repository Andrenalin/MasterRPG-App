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
        parentId: UUID? = nil,
        url: URL? = nil,
        entries: [AudioEntryDataModel] = []
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
    
    var url: URL?
    public var fileUrl: FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: AudioDataModel.typeId.token)
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
    
    var hasAudio: Bool {
        guard category == .folder || category == .playlist else { return url != nil }
        return entryModels.first { entry in
            guard let entryItem = AudioDataModel.model(modelContext: modelContext, id: entry.itemId) else { return false }
            return entryItem.hasAudio
        } != nil
    }
    
    var specialCategory: Bool {
        category == .folder || category == .playlist
    }
    
    var audioList: [AudioModel] {
        guard category == .folder || category == .playlist else { return url == nil ? [] : [itemModel] }
        var list: [AudioModel] = []
        entryModels.forEach { entry in
            if let entryItem = AudioDataModel.model(modelContext: modelContext, id: entry.itemId) {
                list.append(contentsOf: entryItem.audioList)
            }
        }
        return list
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
    static func model(modelContext: ModelContext?, id: UUID?) -> AudioDataModel? {
        guard let modelContext, let id else { return nil }
        let fetchDesc = FetchDescriptor<AudioDataModel>()
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
    static var newItem: AudioDataModel {
        AudioDataModel(name: "", information: "", category: .music, tags: [])
    }
    
    var itemModel: AudioModel {
        let entries = entryModels.map { $0.entryModel }
        return AudioModel(
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
