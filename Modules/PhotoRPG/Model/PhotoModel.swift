// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// Equality cache for PhotoModel version-based comparisons
private final class PhotoModelEqualityCache: @unchecked Sendable {
    private struct CacheKey: Hashable {
        let lhsId: UUID
        let rhsId: UUID
        let lhsVersion: Int
        let rhsVersion: Int
    }

    private var cache: [CacheKey: Bool] = [:]
    private let lock = NSLock()
    private let maxCacheSize = 1000

    func get(lhsId: UUID, rhsId: UUID, lhsVersion: Int, rhsVersion: Int) -> Bool? {
        let key = CacheKey(lhsId: lhsId, rhsId: rhsId, lhsVersion: lhsVersion, rhsVersion: rhsVersion)
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    func set(lhsId: UUID, rhsId: UUID, lhsVersion: Int, rhsVersion: Int, result: Bool) {
        let key = CacheKey(lhsId: lhsId, rhsId: rhsId, lhsVersion: lhsVersion, rhsVersion: rhsVersion)

        lock.lock()
        defer { lock.unlock() }

        // Simple cache eviction: clear half the cache when full
        if cache.count >= maxCacheSize {
            let keysToRemove = cache.keys.prefix(maxCacheSize / 2)
            for keyToRemove in keysToRemove {
                cache.removeValue(forKey: keyToRemove)
            }
        }

        cache[key] = result
    }
}

@Observable
public final class PhotoModel: Identifiable, @unchecked Sendable {
    private static let equalityCache = PhotoModelEqualityCache()

    init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .adventure, displayState: Int = 0, degrees: Double = 0, fileUrl: FileUrl? = nil, entries: [PhotoEntryModel] = [], parentId: UUID? = nil) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        degrees_ = CRDT(wrappedValue: degrees)
        fileUrl_ = CRDTDataUpdate(wrappedValue: fileUrl)
        entries_ = CRDTDataUpdate(wrappedValue: entries)
        self.parentId = parentId
    }

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, degrees: CRDT<Double>, fileUrl: CRDTDataUpdate<FileUrl?>, entries: CRDTDataUpdate<[PhotoEntryModel]>, parentId: UUID?) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        degrees_ = degrees
        fileUrl_ = fileUrl
        entries_ = entries
        self.parentId = parentId
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<PhotoModel.CodingKeys> = try decoder.container(keyedBy: PhotoModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: PhotoModel.CodingKeys._id)
        self.name_ = try container.decode(CRDT<String>.self, forKey: PhotoModel.CodingKeys._name_)
        self.description_ = try container.decode(CRDT<String>.self, forKey: PhotoModel.CodingKeys._description_)
        self.tags_ = try container.decode(CRDT<[String]>.self, forKey: PhotoModel.CodingKeys._tags_)
        self.category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: PhotoModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: PhotoModel.CodingKeys._displayState)
        self.degrees_ = try container.decode(CRDT<Double>.self, forKey: PhotoModel.CodingKeys._degrees_)
        self.fileUrl_ = try container.decode(CRDTDataUpdate<FileUrl?>.self, forKey: PhotoModel.CodingKeys._fileUrl_)
        self.entries_ = try container.decode(CRDTDataUpdate<[PhotoEntryModel]>.self, forKey: PhotoModel.CodingKeys._entries_)
        self.parentId = try container.decodeIfPresent(UUID.self, forKey: PhotoModel.CodingKeys._parentId)
    }

    public var id: UUID

    public var name: String {
        get { name_.wrappedValue }
        set { name_.wrappedValue = newValue }
    }
    @ObservationIgnored var name_: CRDT<String>

    public var description: String {
        get { description_.wrappedValue }
        set { description_.wrappedValue = newValue }
    }
    @ObservationIgnored var description_: CRDT<String>

    public var tags: [String] {
        get { tags_.wrappedValue }
        set { tags_.wrappedValue = newValue }
    }
    @ObservationIgnored var tags_: CRDT<[String]>

    public var category: ItemListCategory {
        get { category_.wrappedValue }
        set { category_.wrappedValue = newValue }
    }
    @ObservationIgnored var category_: CRDT<ItemListCategory>

    public var displayState: Int

    public var degrees: Double {
        get { degrees_.wrappedValue }
        set { degrees_.wrappedValue = newValue }
    }
    @ObservationIgnored var degrees_: CRDT<Double>

    public var fileUrl: FileUrl? {
        get { fileUrl_.wrappedValue }
        set { fileUrl_.wrappedValue = newValue }
    }
    @ObservationIgnored var fileUrl_: CRDTDataUpdate<FileUrl?>

    public var entries: [PhotoEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    @ObservationIgnored var entries_: CRDTDataUpdate<[PhotoEntryModel]>

    public var parentId: UUID? = nil
    
    // only game properties
    public var players: [UUID] = []
}

extension PhotoModel: ItemGameReportable, ItemLinkRegistable {}

extension PhotoModel {
    var hasPhoto: Bool {
        fileUrl != nil
    }
}

extension PhotoModel: Comparable {
    public static func < (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension PhotoModel: ItemDiffComparable {
    public func merge(_ other: PhotoModel) -> PhotoModel {
        PhotoModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            degrees: degrees_.merged(other: other.degrees_),
            fileUrl: fileUrl_.merged(other: other.fileUrl_),
            entries: entries_.merged(other: other.entries_),
            parentId: other.parentId
        )
    }

    public func isSame(_ other: PhotoModel) -> Bool {
        // Version-based caching: check if we've already compared these versions
        let lhsVersion = self.version
        let rhsVersion = other.version

        if let cachedResult = Self.equalityCache.get(
            lhsId: self.id,
            rhsId: other.id,
            lhsVersion: lhsVersion,
            rhsVersion: rhsVersion
        ) {
            return cachedResult
        }

        // Fast checks first: cheapest comparisons and most likely to differ
        // Check counts first (O(1) integer comparison)
        guard entries.count == other.entries.count else {
            Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: false)
            return false
        }

        // Check parentId (O(1) UUID comparison, optional so likely different)
        guard parentId == other.parentId else {
            Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: false)
            return false
        }

        // Check update hashes (O(1) integer comparisons, changes frequently)
        guard fileUrl_.update == other.fileUrl_.update,
              entries_.update == other.entries_.update else {
            Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: false)
            return false
        }

        // Check scalar values (O(1) but less likely to differ than above)
        guard degrees == other.degrees,
              category == other.category else {
            Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: false)
            return false
        }

        // Check strings (O(n) but short strings, likely to differ)
        guard name == other.name else {
            Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: false)
            return false
        }

        // Check arrays (O(n) comparisons)
        guard tags == other.tags else {
            Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: false)
            return false
        }

        // Most expensive checks last
        // Check description (potentially long string)
        guard description == other.description else {
            Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: false)
            return false
        }

        // Most expensive: deep equality check on entries array
        for (index, entry) in entries.enumerated() {
            if entry != other.entries[index] {
                Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: false)
                return false
            }
        }

        // Cache and return true
        Self.equalityCache.set(lhsId: self.id, rhsId: other.id, lhsVersion: lhsVersion, rhsVersion: rhsVersion, result: true)
        return true
    }
    
    public var version: Int {
        fileUrl_.update.hashValue
    }
}

extension PhotoModel: ItemDuplicatable {
    public func duplicate() -> PhotoModel {
        let copyName = duplicateName(from: name)
        return PhotoModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, degrees: degrees, fileUrl: nil, entries: entries.map { $0.duplicate() })
    }
}

extension PhotoModel: ItemDataAccessable {
    public static var empty: PhotoModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> PhotoModel {
        PhotoModel(id: id, name: "")
    }
    public static let typeId: NetworkModules = .photo

    public func copy() -> PhotoModel {
        PhotoModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, degrees: degrees_, fileUrl: fileUrl_, entries: entries_, parentId: parentId)
    }
    
    public func filter(_ filter: String) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
    }
    
    public func isEqual(other: PhotoModel) -> Bool {
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

    @MainActor public func replace(with model: PhotoModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        degrees_ <=> model.degrees_
        fileUrl_ <=> model.fileUrl_
        entries_ <=> model.entries_
        parentId <=> model.parentId
        return true
    }

    public subscript(id: UUID) -> PhotoEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return .empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }

    public func urlAdr(linkNumber: Int, entryId: UUID) -> String {
        "\(URL.appScheme)://\(Self.typeId.token)/\(linkNumber)/\(entryId)"
    }

    public func urlName(entryId: UUID) -> String {
        let title = entries.first(where: { $0.id == entryId })?.name ?? name
        return "\(title.withoutLink())"
    }
}

extension PhotoModel: Codable {
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

    final public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<PhotoModel.CodingKeys> = encoder.container(keyedBy: PhotoModel.CodingKeys.self)

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

extension PhotoModel: Equatable, Hashable {
    public static func == (lhs: PhotoModel, rhs: PhotoModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
