// @copyright André Trettin

import CoreRPG
import Foundation
import FoundationModels
import SwiftData

@Model 
public final class CharacterDataModel {
    public init(itemId: UUID = UUID(), diceId: UUID? = nil, photoId: UUID? = nil, photos: [UUID] = [], parentId: UUID? = nil, entries: [CharacterEntryDataModel] = []) {
        self.itemId = itemId
        self.displayState = 0
        
        self.diceId = diceId
        self.photoId = photoId
        self.photos = photos
        self.parentId = parentId
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var itemId: UUID = UUID()
    public var displayState: Int = 0

    var diceId: UUID? = nil
    var photoId: UUID? = nil
    var photos: [UUID] = []
    var parentId: UUID? = nil
    
    @Relationship(deleteRule: .cascade) private var entries_: [CharacterEntryDataModel]? = []
    
    // MARK: Codable
    
    public struct Value: Equatable, Hashable, Codable, Sendable {
        public init(itemId: UUID = UUID(), diceId: UUID? = nil, photoId: UUID? = nil, photos: [UUID] = [], parentId: UUID? = nil, entries: [CharacterEntryDataModel.Value] = [], links: [LinkDataModel.Value] = []) {
            self.itemId = itemId
            self.diceId = diceId
            self.photoId = photoId
            self.photos = photos
            self.parentId = parentId
            self.entries = entries
            self.links = links
        }
        public var itemId: UUID = UUID()
        public var diceId: UUID? = nil
        public var photoId: UUID? = nil
        public var photos: [UUID] = []
        public var parentId: UUID? = nil
        public var entries: [CharacterEntryDataModel.Value] = []
        public var links: [LinkDataModel.Value] = []
    }
    
    convenience init(_ model: Value) {
        self.init(itemId: model.itemId, diceId: model.diceId, photoId: model.photoId, photos: model.photos, parentId: model.parentId, entries: [])
        self.entries = model.entries.map { CharacterEntryDataModel($0) }
    }
    
    @MainActor
    var codableModel: Value {
        Value(
            itemId: itemId,
            diceId: diceId,
            photoId: photoId,
            photos: photos,
            parentId: parentId,
            entries: entries.map {
                $0.codableModel
            },
            links: entries.flatMap {
                $0.links
            }
        )
    }
    
    func replace(_ model: Value) {
        itemId = model.itemId
        diceId = model.diceId
        photoId = model.photoId
        photos = model.photos
        parentId = model.parentId
        entries = model.entries.map { CharacterEntryDataModel($0) }
    }
    
    func duplicate(newItemId: UUID) -> CharacterDataModel {
        CharacterDataModel(
            itemId: newItemId,
            diceId: diceId,
            photoId: photoId,
            photos: photos,
            parentId: parentId,
            entries: entries.map { $0.duplicate(newItemId: newItemId, newEntryId: UUID()) }
        )
    }
}

extension CharacterDataModel {
    public var entries: [CharacterEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }
    
    public subscript(id: UUID) -> CharacterEntryDataModel {
        get { entries.first(where: { $0.entryId == id }) ?? CharacterEntryDataModel(itemId: itemId) }
        set(newValue) {
            guard let index = entries.firstIndex(where: { $0.entryId == id }) else { return }
            entries[index] = newValue
        }
    }

}

extension CharacterDataModel: ModelCachable {
    public static func newModel(for itemId: UUID) -> CharacterDataModel {
        CharacterDataModel(itemId: itemId)
    }
}

extension CharacterDataModel: EntryEditModel {}


// MARK: - Generable

extension CharacterDataModel {
    @Generable(description: "The character description")
    public struct GenValue: Equatable, Hashable, Codable, Sendable {
        public init(name: String, information: String, tags: [String], entries: [CharacterEntryDataModel.GenValue] = []) {
            self.name = name
            self.information = information
            self.tags = tags
            self.entries = entries
        }

        @Guide(description: "The name of the character or the group of values")
        public var name: String
        @Guide(description: "A description about the character ot the group")
        public var information: String
        @Guide(description: "A tag description", .maximumCount(5))
        public var tags: [String]
        @Guide(description: "A character has many named values like key value pairs")
        public var entries: [CharacterEntryDataModel.GenValue] = []
    }
}
