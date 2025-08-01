// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class PdfDataModel {
    init(
        id: UUID = UUID(),
        name: String = "",
        information: String = "",
        category: ItemListCategory = .adventure,
        tags: [String] = [],
        displayState: Int = 0,
        parentId: UUID? = nil,
        url: URL? = nil,
        entries: [PdfEntryDataModel] = [],
        bookmarks: [PdfBookmarkDataModel] = []
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
        self.bookmarks = bookmarks
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
        return FileUrl(fileId: id, url: url, location: .cloud, module: PdfDataModel.typeId.token)
    }
    
    @Relationship(deleteRule: .cascade) private var entries: [PdfEntryDataModel]? = []
    @Relationship(deleteRule: .cascade) private var bookmarks: [PdfBookmarkDataModel]? = []
}

extension PdfDataModel {
    public var entryModels: [PdfEntryDataModel] {
        get {
            guard let all = entries else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries = newValue
        }
    }

    func entryOrNew(for id: UUID) -> PdfEntryDataModel {
        if let entry = entryModels.first(where: { $0.id == id }) {
            return entry
        }
        return PdfEntryDataModel(id: id)
    }

    public var bookmarksModels: [PdfBookmarkDataModel] {
        get {
            guard let all = bookmarks else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            bookmarks = newValue
        }
    }

    func bookmarkOrNew(for id: UUID) -> PdfBookmarkDataModel {
        if let entry = bookmarksModels.first(where: { $0.id == id }) {
            return entry
        }
        return PdfBookmarkDataModel(id: id)
    }

    var specialCategory: Bool {
        category == .folder || category == .collection
    }
}

extension PdfDataModel {
    func reset(name: String) {
        _nameLWW.wrappedValue = name
        self.name = name
    }
    
    func reset(information: String) {
        _informationLWW.wrappedValue = information
        self.information = information
    }
}

extension PdfDataModel {
    static func model(modelContext: ModelContext?, id: UUID?) -> PdfDataModel? {
        guard let modelContext, let id else { return nil }
        let fetchDesc = FetchDescriptor<PdfDataModel>()
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

extension PdfDataModel: HasPhotoModel {}
extension PdfDataModel: ItemDataAccessable {
    public static var typeId: NetworkModules { .pdf }

    public subscript(id: UUID) -> PdfEntryDataModel {
        get {
            entryModels.first(where: { $0.id == id }) ?? PdfEntryDataModel(id: id)
        }
        set(newValue) {
            guard let index = entryModels.firstIndex(where: { $0.id == id }) else { return }
            entryModels[index] = newValue
        }
    }
}

extension PdfDataModel: ListItemFolderable {
    public var isFolder: Bool {
        category == .folder
    }
    public var subItems: [PdfDataModel] {
        guard isFolder else { return [] }
        return []
    }
}

extension PdfDataModel {
    static var newItem: PdfDataModel {
        PdfDataModel(name: "", information: "", category: .adventure, tags: [])
    }
    
    var itemModel: PdfModel {
        let entries = entryModels.map { $0.entryModel }
        return PdfModel(
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
