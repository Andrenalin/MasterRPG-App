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
    public var url: URL?
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
    
    @MainActor public var specialCategory: Bool {
        category == .folder || category == AudioDataModel.collectionCategory
    }
    
    var hasAudio: Bool {
        guard category == .folder || category == .playlist else { return url != nil }
        return entryModels.first { entry in
            guard let entryItem = AudioDataModel.model(modelContext: modelContext, id: entry.childId) else { return false }
            return entryItem.hasAudio
        } != nil
    }
    
    var audioList: [AudioModel] {
        guard category == .folder || category == .playlist else { return url == nil ? [] : [itemModel] }
        var list: [AudioModel] = []
        entryModels.forEach { entry in
            if let entryItem = AudioDataModel.model(modelContext: modelContext, id: entry.childId) {
                list.append(contentsOf: entryItem.audioList)
            }
        }
        return list
    }
}

extension AudioDataModel {
    public static func model(modelContext: ModelContext?, id: UUID?) -> AudioDataModel? {
        guard let modelContext, let id else { return nil }
        let fetchDesc = FetchDescriptor<AudioDataModel>()
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

extension AudioDataModel: ItemDataAccessable {
    public static var typeId: NetworkModules { .audio }
    public subscript(id: UUID) -> AudioEntryDataModel {
        get { entryModels.first(where: { $0.id == id }) ?? AudioEntryDataModel(id: id) }
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
    public func reset(entries: [AudioEntryDataModel]) {
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

extension AudioDataModel: ListItemFolderable {
    public var isFolder: Bool {
        category == .folder
    }
    @MainActor public var subItems: ([AudioDataModel], [UUID: UUID]) {
        guard specialCategory else { return ([], [:]) }
        var entryIds: [UUID: UUID] = [:]
        let items: [AudioDataModel] = entryModels.compactMap {
            guard let childId = $0.childId, childId != id else { return nil }
            if let model = AudioDataModel.model(modelContext: modelContext, id: childId), model.displayState == 0 {
                entryIds[childId] = $0.id
                return model
            }
            return nil
        }
        return (items, entryIds)
    }
    @MainActor public static let dropItem: AudioDataModel = AudioDataModel(id: UUID(), name: "Audio", information: "Drop or select an Audio", category: .drop)
    @MainActor public static var collectionCategory: ItemListCategory = .playlist
}

extension AudioDataModel: ItemDataModelable {
    public typealias Model = AudioDataModel
    public typealias ExchangeModel = AudioModel
}

extension AudioDataModel {
    public static var newItem: AudioDataModel {
        AudioDataModel(name: "", information: "", category: .music, tags: [])
    }
    
    public var itemModel: AudioModel {
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
