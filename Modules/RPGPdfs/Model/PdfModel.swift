// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

#if canImport(PDFKit)
import PDFKit
#endif

#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif

@Observable
public final class PdfModel: Identifiable, @unchecked Sendable {
    init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, fileUrl: FileUrl? = nil, entries: [PdfEntryModel] = []) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        fileUrl_ = CRDTDataUpdate(wrappedValue: fileUrl)
        entries_ = CRDTDataUpdate(wrappedValue: entries)
    }

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[PdfEntryModel]>) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        fileUrl_ = fileUrl
        entries_ = entries
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<PdfModel.CodingKeys> = try decoder.container(keyedBy: PdfModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: PdfModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: PdfModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: PdfModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: PdfModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: PdfModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: PdfModel.CodingKeys._displayState)
        self._fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: PdfModel.CodingKeys._fileUrl_)
        self._entries_ = try container.decode(CRDTDataUpdate<[PdfEntryModel]>.self, forKey: PdfModel.CodingKeys._entries_)
    }

    public var id: UUID

    public var name: String {
        get { name_.wrappedValue }
        set { name_.wrappedValue = newValue }
    }
    var name_: CRDT<String>

    public var description: String {
        get { description_.wrappedValue }
        set { description_.wrappedValue = newValue }
    }
    var description_: CRDT<String>

    public var tags: [String] {
        get { tags_.wrappedValue }
        set { tags_.wrappedValue = newValue }
    }
    var tags_: CRDT<[String]>

    public var category: ItemListCategory {
        get { category_.wrappedValue }
        set { category_.wrappedValue = newValue }
    }
    var category_: CRDT<ItemListCategory>

    public var displayState: Int

    public var fileUrl: FileUrl? {
        get { fileUrl_.wrappedValue }
        set { fileUrl_.wrappedValue = newValue }
    }
    public var fileUrl_: CRDTDataUpdate<FileUrl?>

    public var entries: [PdfEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    public var entries_: CRDTDataUpdate<[PdfEntryModel]>
}

extension PdfModel: Comparable {
    public var hasPdf: Bool {
        fileUrl != nil
    }

    public static func < (lhs: PdfModel, rhs: PdfModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension PdfModel:  ItemLinkRegistable {}

extension PdfModel: ItemDiffComparable {
    public func merge(_ other: PdfModel) -> PdfModel {
        PdfModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            fileUrl: fileUrl_.merged(other: other.fileUrl_),
            entries: entries_.merged(other: other.entries_)
        )
    }

    public func isSame(_ other: PdfModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        fileUrl_.update == other.fileUrl_.update &&
        entries_.update == other.entries_.update &&
        // santity checks
        entries.count == other.entries.count &&
        entries.enumerated().allSatisfy { index, entry in
            entry == other.entries[index]
        }
    }
    
    public var version: Int {
        fileUrl_.update.hashValue
    }
}

extension PdfModel: ItemDuplicatable {
    public func duplicate() -> PdfModel {
        let copyName = duplicateName(from: name)
        return PdfModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, fileUrl: nil, entries: entries.map { $0.duplicate() })
    }
}

extension PdfModel: ItemDataAccessable {
    public static var empty: PdfModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> PdfModel {
        PdfModel(id: id, name: "")
    }
    public static let typeId: NetworkModules = .pdf

    public func copy() -> PdfModel {
        PdfModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, fileUrl: fileUrl_, entries: entries_)
    }

    public func filter(_ filter: String) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
    }

    public func isEqual(other: PdfModel) -> Bool {
        self == other
    }

    public var isGroupHiddenToggle: Bool {
        get { isGroupHidden }
        set {
            if newValue {
                displayState = DisplayStateMask.groupHidden.set(on: displayState)
            } else {
                displayState = DisplayStateMask.groupHidden.reset(on: displayState)
            }
        }
    }

    public func replace(with model: PdfModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        fileUrl_ <=> model.fileUrl_
        entries_ <=> model.entries_
        return true
    }

    public subscript(id: UUID) -> PdfEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return .empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }
}

extension PdfModel: Codable {
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _fileUrl_
        case _entries_
    }

    public final func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<PdfModel.CodingKeys> = encoder.container(keyedBy: PdfModel.CodingKeys.self)

        try container.encode(self._id, forKey: PdfModel.CodingKeys._id)
        try container.encode(self._name_, forKey: PdfModel.CodingKeys._name_)
        try container.encode(self._description_, forKey: PdfModel.CodingKeys._description_)
        try container.encode(self._tags_, forKey: PdfModel.CodingKeys._tags_)
        try container.encode(self._category_, forKey: PdfModel.CodingKeys._category_)
        try container.encode(self._displayState, forKey: PdfModel.CodingKeys._displayState)
        try container.encode(self._fileUrl_, forKey: PdfModel.CodingKeys._fileUrl_)
        try container.encode(self._entries_, forKey: PdfModel.CodingKeys._entries_)
    }
}

extension PdfModel: Equatable, Hashable {
    public static func == (lhs: PdfModel, rhs: PdfModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
