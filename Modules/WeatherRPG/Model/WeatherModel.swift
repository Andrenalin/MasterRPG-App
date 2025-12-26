// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

@Observable
public final class WeatherModel: Identifiable, @unchecked Sendable {
    public init(id: UUID, name: String, description: String, tags: [String], category: ItemListCategory = .scenario, displayState: Int = 0, weatherUpdate: UUID = UUID(), time: Double, cloudThickness: Cloud.Thickness, stormType: Storm.Contents, rainAngle: Double, rainIntensity: Double, lightningFrequency: Double, lightningMaxBolts: Double, lightningForkProbability: Double, photoId: UUID?, entries: [ChildEntryModel] = [], parentId: UUID? = nil) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        weatherUpdate_ = CRDT(wrappedValue: weatherUpdate)
        self.time = time
        self.cloudThickness = cloudThickness
        self.stormType = stormType
        self.rainAngle = rainAngle
        self.rainIntensity = rainIntensity
        self.lightningFrequency = lightningFrequency
        self.lightningMaxBolts = lightningMaxBolts
        self.lightningForkProbability = lightningForkProbability
        self.photoId = photoId
        entries_ = CRDTDataUpdate(wrappedValue: entries)
        self.parentId = parentId
    }

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, weatherUpdate: CRDT<UUID>, time: Double, cloudThickness: Cloud.Thickness, stormType: Storm.Contents, rainAngle: Double, rainIntensity: Double, lightningFrequency: Double, lightningMaxBolts: Double, lightningForkProbability: Double, photoId: UUID?, entries: CRDTDataUpdate<[ChildEntryModel]>, parentId: UUID?) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        weatherUpdate_ = weatherUpdate
        self.time = time
        self.cloudThickness = cloudThickness
        self.stormType = stormType
        self.rainAngle = rainAngle
        self.rainIntensity = rainIntensity
        self.lightningFrequency = lightningFrequency
        self.lightningMaxBolts = lightningMaxBolts
        self.lightningForkProbability = lightningForkProbability
        self.photoId = photoId
        entries_ = entries
        self.parentId = parentId
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<WeatherModel.CodingKeys> = try decoder.container(keyedBy: WeatherModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: WeatherModel.CodingKeys._id)
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

extension WeatherModel {
    var rainDirection: Bool {
        get { rainAngle >= 0 }
        set { rainAngle *= -1 }
    }

    var children: [WeatherModel] {
        [self]
    }
}

extension WeatherModel: Comparable {
    public static func < (lhs: WeatherModel, rhs: WeatherModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension WeatherModel: ItemLinkRegistable {
    @MainActor
    public var linkRegisterModels: [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, typeId: .weather)
        if let photoId {
            return [LinkRegisterModel(name: "", source: source, destination: ItemRowModel(itemId: photoId, typeId: .photo))]
        }
        return []
    }
}

extension WeatherModel: ItemDiffComparable {
    public func merge(_ other: WeatherModel) -> WeatherModel {
        let merged = weatherUpdate_.merged(other: other.weatherUpdate_)
        let shouldUpdate = merged.wrappedValue == weatherUpdate_.wrappedValue
        return WeatherModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: other.displayState,
            weatherUpdate: merged,
            time: shouldUpdate ? time : other.time,
            cloudThickness: shouldUpdate ? cloudThickness : other.cloudThickness,
            stormType: shouldUpdate ? stormType : other.stormType,
            rainAngle: shouldUpdate ? rainAngle : other.rainAngle,
            rainIntensity: shouldUpdate ? rainIntensity : other.rainIntensity,
            lightningFrequency: shouldUpdate ? lightningFrequency : other.lightningFrequency,
            lightningMaxBolts: shouldUpdate ? lightningMaxBolts : other.lightningMaxBolts,
            lightningForkProbability: shouldUpdate ? lightningForkProbability : other.lightningForkProbability,
            photoId: shouldUpdate ? photoId : other.photoId,
            entries: entries_.merged(other: other.entries_),
            parentId: other.parentId
        )
    }

    public func isSame(_ other: WeatherModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        weatherUpdate_.wrappedValue == other.weatherUpdate_.wrappedValue &&
        time == other.time &&
        cloudThickness == other.cloudThickness &&
        stormType == other.stormType &&
        rainAngle == other.rainAngle &&
        rainIntensity == other.rainIntensity &&
        lightningFrequency == other.lightningFrequency &&
        lightningMaxBolts == other.lightningMaxBolts &&
        lightningForkProbability == other.lightningForkProbability &&
        photoId == other.photoId &&
        entries_.update == other.entries_.update &&
        parentId == other.parentId
    }
}

extension WeatherModel: ItemDuplicatable {
    public func duplicate() -> WeatherModel {
        let copyName = duplicateName(from: name)
        return WeatherModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, time: time, cloudThickness: cloudThickness, stormType: stormType, rainAngle: rainAngle, rainIntensity: rainIntensity, lightningFrequency: lightningFrequency, lightningMaxBolts: lightningMaxBolts, lightningForkProbability: lightningForkProbability, photoId: photoId, entries: entries.map { $0.duplicate() }, parentId: parentId)
    }
}

extension WeatherModel: ItemDataAccessable {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    public static var empty: WeatherModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> WeatherModel {
        WeatherModel(id: id, name: "", description: "", tags: [], time: 0.0, cloudThickness: .none, stormType: .none, rainAngle: 0, rainIntensity: 0, lightningFrequency: 0, lightningMaxBolts: 0, lightningForkProbability: 0, photoId: nil)
    }
    public static let typeId: NetworkModules = .weather

    public func copy() -> WeatherModel {
        WeatherModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, weatherUpdate: weatherUpdate_, time: time, cloudThickness: cloudThickness, stormType: stormType, rainAngle: rainAngle, rainIntensity: rainIntensity, lightningFrequency: lightningFrequency, lightningMaxBolts: lightningMaxBolts, lightningForkProbability: lightningForkProbability, photoId: photoId, entries: entries_, parentId: parentId)
    }

    public func filter(_ filter: String) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
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
    
    public func replace(with model: WeatherModel) -> Bool {
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
        parentId <=> parentId
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

extension WeatherModel: Codable {
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

    public final func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<WeatherModel.CodingKeys> = encoder.container(keyedBy: WeatherModel.CodingKeys.self)

        try container.encode(self._id, forKey: WeatherModel.CodingKeys._id)
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

extension WeatherModel: Equatable, Hashable {
    public static func == (lhs: WeatherModel, rhs: WeatherModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
