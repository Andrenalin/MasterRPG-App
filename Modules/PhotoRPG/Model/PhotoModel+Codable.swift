// @copyright André Trettin

import CoreRPG
import Foundation

// `init(from:)` stays on the primary type declaration (Model/PhotoModel.swift) since it's
// a designated initializer assigning every stored property directly — only the Encodable
// half (CodingKeys + encode(to:)) is self-contained enough to extract. See CODE_AUDIT §9.10.
extension PhotoModel: nonisolated Codable {
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _degrees_
        case _fileUrl_
        case _entries_
        case _parentId
    }

    nonisolated final public func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<PhotoModel.CodingKeys> = encoder.container(keyedBy: PhotoModel.CodingKeys.self)

            // Read through the `@Observable`-synthesized computed properties (`name_`,
            // `description_`, ...), not their `private` backing storage (`_name_`, ...) —
            // that backing storage is only accessible from the same file as the primary
            // type declaration. Same values either way; this just goes through the
            // tracked getter instead of the raw field. See CODE_AUDIT §9.10.
            try container.encode(self.id, forKey: PhotoModel.CodingKeys._id)
            try container.encode(self.name_, forKey: PhotoModel.CodingKeys._name_)
            try container.encode(self.description_, forKey: PhotoModel.CodingKeys._description_)
            try container.encode(self.tags_, forKey: PhotoModel.CodingKeys._tags_)
            try container.encode(self.category_, forKey: PhotoModel.CodingKeys._category_)
            try container.encode(self.displayState, forKey: PhotoModel.CodingKeys._displayState)
            try container.encode(self.degrees_, forKey: PhotoModel.CodingKeys._degrees_)
            try container.encode(self.fileUrl_, forKey: PhotoModel.CodingKeys._fileUrl_)
            try container.encode(self.entries_, forKey: PhotoModel.CodingKeys._entries_)
            try container.encodeIfPresent(self.parentId, forKey: PhotoModel.CodingKeys._parentId)
        }
    }
}
