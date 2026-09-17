// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as WeatherSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class WeatherModel: nonisolated Identifiable {
    nonisolated public init(id: UUID, name: String, description: String, tags: [String], category: ItemListCategory = .scenario, displayState: Int = 0, weatherUpdate: UUID = UUID(), time: Double, cloudThickness: Cloud.Thickness, stormType: Storm.Contents, rainAngle: Double, rainIntensity: Double, lightningFrequency: Double, lightningMaxBolts: Double, lightningForkProbability: Double, photoId: UUID?, entries: [ChildEntryModel] = [], parentId: UUID? = nil) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _weatherUpdate_ = CRDT(wrappedValue: weatherUpdate)
        self._time = time
        self._cloudThickness = cloudThickness
        self._stormType = stormType
        self._rainAngle = rainAngle
        self._rainIntensity = rainIntensity
        self._lightningFrequency = lightningFrequency
        self._lightningMaxBolts = lightningMaxBolts
        self._lightningForkProbability = lightningForkProbability
        self._photoId = photoId
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        self._parentId = parentId
    }

    nonisolated init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, weatherUpdate: CRDT<UUID>, time: Double, cloudThickness: Cloud.Thickness, stormType: Storm.Contents, rainAngle: Double, rainIntensity: Double, lightningFrequency: Double, lightningMaxBolts: Double, lightningForkProbability: Double, photoId: UUID?, entries: CRDTDataUpdate<[ChildEntryModel]>, parentId: UUID?) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _weatherUpdate_ = weatherUpdate
        self._time = time
        self._cloudThickness = cloudThickness
        self._stormType = stormType
        self._rainAngle = rainAngle
        self._rainIntensity = rainIntensity
        self._lightningFrequency = lightningFrequency
        self._lightningMaxBolts = lightningMaxBolts
        self._lightningForkProbability = lightningForkProbability
        self._photoId = photoId
        _entries_ = entries
        self._parentId = parentId
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<WeatherModel.CodingKeys> = try decoder.container(keyedBy: WeatherModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: WeatherModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: WeatherModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: WeatherModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: WeatherModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: WeatherModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: WeatherModel.CodingKeys._displayState)
        self._weatherUpdate_ = try container.decode(CRDT<UUID>.self, forKey: WeatherModel.CodingKeys._weatherUpdate_)
        self._time = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._time)
        self._cloudThickness = try container.decode(Cloud.Thickness.self, forKey: WeatherModel.CodingKeys._cloudThickness)
        self._stormType = try container.decode(Storm.Contents.self, forKey: WeatherModel.CodingKeys._stormType)
        self._rainAngle = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._rainAngle)
        self._rainIntensity = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._rainIntensity)
        self._lightningFrequency = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._lightningFrequency)
        self._lightningMaxBolts = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._lightningMaxBolts)
        self._lightningForkProbability = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._lightningForkProbability)
        self._photoId = try container.decodeIfPresent(UUID.self, forKey: WeatherModel.CodingKeys._photoId)
        self._entries_ = try container.decodeIfPresent(CRDTDataUpdate<[ChildEntryModel]>.self, forKey: WeatherModel.CodingKeys._entries_) ?? CRDTDataUpdate<[ChildEntryModel]>(wrappedValue: [])
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: WeatherModel.CodingKeys._parentId)
    }

    // `let`: nonisolated access (Identifiable, hashing) per SE-0434.
    public let id: UUID
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

    var weatherUpdate_: CRDT<UUID>

    public var time: Double
    public var cloudThickness: Cloud.Thickness

    public var stormType: Storm.Contents
    public var rainAngle: Double
    public var rainIntensity: Double

    public var lightningFrequency: Double
    public var lightningMaxBolts: Double
    public var lightningForkProbability: Double

    public var photoId: UUID?
    
    public var entries: [ChildEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[ChildEntryModel]>

    public var parentId: UUID? = nil
}

// `encode(to:)` reads the @Observable macro's raw backing storage (`_name_` etc.,
// not the tracked `name_` accessor) to avoid registering observation access during
// encode — that storage is macro-synthesized `private`, so this conformance must
// stay in the same file as the class declaration; see CODE_AUDIT_Weather §9.7.
extension WeatherModel: nonisolated Codable {
    public enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _weatherUpdate_
        case _time
        case _cloudThickness
        case _stormType
        case _rainAngle
        case _rainIntensity
        case _lightningFrequency
        case _lightningMaxBolts
        case _lightningForkProbability
        case _photoId
        case _entries_
        case _parentId
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<WeatherModel.CodingKeys> = encoder.container(keyedBy: WeatherModel.CodingKeys.self)

            try container.encode(self.id, forKey: WeatherModel.CodingKeys._id)
            try container.encode(self._name_, forKey: WeatherModel.CodingKeys._name_)
            try container.encode(self._description_, forKey: WeatherModel.CodingKeys._description_)
            try container.encode(self._tags_, forKey: WeatherModel.CodingKeys._tags_)
            try container.encode(self._category_, forKey: WeatherModel.CodingKeys._category_)
            try container.encode(self._displayState, forKey: WeatherModel.CodingKeys._displayState)
            try container.encode(self._weatherUpdate_, forKey: WeatherModel.CodingKeys._weatherUpdate_)
            try container.encode(self._time, forKey: WeatherModel.CodingKeys._time)
            try container.encode(self._cloudThickness, forKey: WeatherModel.CodingKeys._cloudThickness)
            try container.encode(self._stormType, forKey: WeatherModel.CodingKeys._stormType)
            try container.encode(self._rainAngle, forKey: WeatherModel.CodingKeys._rainAngle)
            try container.encode(self._rainIntensity, forKey: WeatherModel.CodingKeys._rainIntensity)
            try container.encode(self._lightningFrequency, forKey: WeatherModel.CodingKeys._lightningFrequency)
            try container.encode(self._lightningMaxBolts, forKey: WeatherModel.CodingKeys._lightningMaxBolts)
            try container.encode(self._lightningForkProbability, forKey: WeatherModel.CodingKeys._lightningForkProbability)
            try container.encodeIfPresent(self._photoId, forKey: WeatherModel.CodingKeys._photoId)
            try container.encode(self._entries_, forKey: WeatherModel.CodingKeys._entries_)
            try container.encodeIfPresent(self._parentId, forKey: WeatherModel.CodingKeys._parentId)


        }
    }
}

extension WeatherModel {
    var rainDirection: Bool {
        get { rainAngle >= 0 }
        set {
            // `abs(rainAngle)` alone is a no-op at rainAngle == 0 (and `-0.0 >= 0`
            // is still true), so a zero magnitude falls back to a visible default.
            let magnitude = abs(rainAngle) > 0 ? abs(rainAngle) : 1
            rainAngle = newValue ? magnitude : -magnitude
        }
    }
}

extension WeatherModel: nonisolated Comparable {
    nonisolated public static func < (lhs: WeatherModel, rhs: WeatherModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension WeatherModel: nonisolated ItemLinkRegistable {
    @MainActor public func changedLinkRegisterModels(oldValue: WeatherModel) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []
        
        if oldValue.photoId != photoId {
            let modelSource = ItemRowModel(itemId: id, typeId: .adventure)
            if let photoId {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: photoId, typeId: .photo)))
            }
            if let oldPhotoId = oldValue.photoId {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: oldPhotoId, typeId: .photo)))
            }
        }
        
        return (added, removed)
    }
}

extension WeatherModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> WeatherModel {
        return assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            return WeatherModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, time: time, cloudThickness: cloudThickness, stormType: stormType, rainAngle: rainAngle, rainIntensity: rainIntensity, lightningFrequency: lightningFrequency, lightningMaxBolts: lightningMaxBolts, lightningForkProbability: lightningForkProbability, photoId: photoId, entries: entries.map { $0.duplicate() }, parentId: parentId)
    
        }
    }
}

// `nonisolated ItemDataAccessable` conformance must stay in this file: Swift
// requires a class's `Sendable`-implying conformances to be co-located with the
// class declaration, or it's a build warning today ("will be an error in a
// future Swift language mode"). See CODE_AUDIT_Weather §9.7.
extension WeatherModel: nonisolated ItemDataAccessable {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    nonisolated public static var empty: WeatherModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> WeatherModel {
        WeatherModel(id: id, name: "", description: "", tags: [], time: 0.0, cloudThickness: .none, stormType: .none, rainAngle: 0, rainIntensity: 0, lightningFrequency: 0, lightningMaxBolts: 0, lightningForkProbability: 0, photoId: nil)
    }
    nonisolated public static let typeId: NetworkModules = .weather

    public func copy() -> WeatherModel {
        WeatherModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, weatherUpdate: weatherUpdate_, time: time, cloudThickness: cloudThickness, stormType: stormType, rainAngle: rainAngle, rainIntensity: rainIntensity, lightningFrequency: lightningFrequency, lightningMaxBolts: lightningMaxBolts, lightningForkProbability: lightningForkProbability, photoId: photoId, entries: entries_, parentId: parentId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedStandardContains(filter) || description.localizedStandardContains(filter)) else { return true }
        return false
    }

    public func isEqual(other: WeatherModel) -> Bool {
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

    @MainActor public func replace(with model: WeatherModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        weatherUpdate_.wrappedValue = UUID()
        time <=> model.time
        cloudThickness <=> model.cloudThickness
        stormType <=> model.stormType
        rainAngle <=> model.rainAngle
        rainIntensity <=> model.rainIntensity
        lightningFrequency <=> model.lightningFrequency
        lightningMaxBolts <=> model.lightningMaxBolts
        lightningForkProbability <=> model.lightningForkProbability
        photoId <=> model.photoId
        entries_ <=> model.entries_
        parentId <=> model.parentId
        return true
    }

    public subscript(id: UUID) -> ChildEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return ChildEntryModel.empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }

    public func urlName(entryId: UUID) -> String {
        urlName()
    }

    public func url(linkNumber: Int, entryId: UUID) -> String {
        url(linkNumber: 0)
    }
}

extension WeatherModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: WeatherModel, rhs: WeatherModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
