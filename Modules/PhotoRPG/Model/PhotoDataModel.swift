// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class PhotoDataModel {
    init(id: UUID = UUID(), name: String = "", information: String = "", category: ItemListCategory = .adventure, tags: [String] = [], displayState: Int32 = 0, degrees: Double = 0, url: URL? = nil, entries: [PhotoEntryDataModel]? = nil) {
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
    var name: String = ""
    var information: String = ""
    private var _nameLWW: CRDT<String> = CRDT(wrappedValue: "")
    private var _informationLWW: CRDT<String> = CRDT(wrappedValue: "")

    var category: ItemListCategory = ItemListCategory.adventure
    var tags: [String] = []
    var displayState: Int32 = 0

    var degrees: Double = 0
    var url: URL?
    var fileUrl: FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: "Photos")
    }

    @Relationship(deleteRule: .cascade) var entries: [PhotoEntryDataModel]?
    
    var nameLLW: String {
        _nameLWW.rawValue
    }
    
    func reset(name: String) {
        do {
            try modelContext?.transaction {
                _nameLWW.wrappedValue = name
                self.name = name
            }
        } catch {
            modelContext?.rollback()
        }
    }
}

extension PhotoDataModel {
    static func model(modelContext: ModelContext, id: UUID?) -> PhotoDataModel? {
        guard let id else { return nil }
        let fetchDesc = FetchDescriptor<PhotoDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        return models?.first { $0.id == id }
    }

    var entriesModel: [PhotoEntryDataModel] {
        get {
            guard let all = entries else {
                return []
            }
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
