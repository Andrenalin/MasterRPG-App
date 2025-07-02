// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftData

@Model
public final class PhotoDataModel {
    init(id: UUID = UUID(), name: String = "", information: String = "", photoCategory: String = "", tags: String = "", displayState: Int32 = 0, degrees: String = "", entriesUpdate: String = "", fileUrl: String = "", fileUrlUpdate: String = "", entries: [PhotoEntryDataModel]? = nil) {
        self.id = id
        self.name = CRDT(wrappedValue: name)
        self.information = information
        self.category = photoCategory
        self.tags = tags
        self.displayState = displayState
        self.degrees = degrees
        self.entriesUpdate = entriesUpdate
        self.fileUrl = fileUrl
        self.fileUrlUpdate = fileUrlUpdate
        self.entries = entries
    }

    @Attribute(.preserveValueOnDeletion)
    public var id: UUID
    var name: CRDT<String> = CRDT(wrappedValue: "")
    var information: String = ""
    var category: String = ""
    var tags: String = ""
    var displayState: Int32 = 0

    var degrees: String = ""
    var entriesUpdate: String = ""
    var fileUrl: String = ""
    var fileUrlUpdate: String = ""
    
    @Relationship(deleteRule: .cascade) var entries: [PhotoEntryDataModel]?
}

extension PhotoDataModel {
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
