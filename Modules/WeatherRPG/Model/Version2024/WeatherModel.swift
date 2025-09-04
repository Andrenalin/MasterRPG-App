// @copyright André Trettin

import CoreRPG
import Foundation

struct WeatherModel: Identifiable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, weatherUpdate: CRDT<UUID>, time: Double = 0, cloudThickness: Cloud.Thickness = .none, stormType: Storm.Contents = .none, rainAngle: Double = 0, rainIntensity: Double = 0, lightningFrequency: Double = 0, lightningMaxBolts: Double = 0, lightningForkProbability: Double = 0, photoId: UUID? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.weatherUpdate = weatherUpdate
        self.time = time
        self.cloudThickness = cloudThickness
        self.stormType = stormType
        self.rainAngle = rainAngle
        self.rainIntensity = rainIntensity
        self.lightningFrequency = lightningFrequency
        self.lightningMaxBolts = lightningMaxBolts
        self.lightningForkProbability = lightningForkProbability
        self.photoId = photoId
    }

    var id: UUID
    var name: CRDT<String> = CRDT<String>(wrappedValue: "")
    var description: CRDT<String> = CRDT<String>(wrappedValue: "")
    var tags: CRDT<[String]> = CRDT<[String]>(wrappedValue: [])
    var category: CRDT<ItemListCategory> = CRDT<ItemListCategory>(wrappedValue: .scenario)
    var displayState: Int = 0
    var weatherUpdate: CRDT<UUID> = CRDT<UUID>(wrappedValue: UUID())
    var time: Double = 0
    var cloudThickness: Cloud.Thickness = .none
    var stormType: Storm.Contents = .none
    var rainAngle: Double = 0
    var rainIntensity: Double = 0
    var lightningFrequency: Double = 0
    var lightningMaxBolts: Double = 0
    var lightningForkProbability: Double = 0
    var photoId: UUID? = nil
    
    var rainDirection: Bool {
        get { rainAngle >= 0 }
        set { rainAngle *= -1 }
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<WeatherModel.CodingKeys> = try decoder.container(keyedBy: WeatherModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: WeatherModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: WeatherModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: WeatherModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: WeatherModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: WeatherModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: WeatherModel.CodingKeys._displayState)
        self.weatherUpdate = try container.decode(CRDT<UUID>.self, forKey: WeatherModel.CodingKeys._weatherUpdate_)
        self.time = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._time)
        self.cloudThickness = try container.decode(Cloud.Thickness.self, forKey: WeatherModel.CodingKeys._cloudThickness)
        self.stormType = try container.decode(Storm.Contents.self, forKey: WeatherModel.CodingKeys._stormType)
        self.rainAngle = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._rainAngle)
        self.rainIntensity = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._rainIntensity)
        self.lightningFrequency = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._lightningFrequency)
        self.lightningMaxBolts = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._lightningMaxBolts)
        self.lightningForkProbability = try container.decode(Double.self, forKey: WeatherModel.CodingKeys._lightningForkProbability)
        self.photoId = try container.decodeIfPresent(UUID.self, forKey: WeatherModel.CodingKeys._photoId)
    }

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
    }

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<WeatherModel.CodingKeys> = encoder.container(keyedBy: WeatherModel.CodingKeys.self)

        try container.encode(self.id, forKey: WeatherModel.CodingKeys._id)
        try container.encode(self.name, forKey: WeatherModel.CodingKeys._name_)
        try container.encode(self.description, forKey: WeatherModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: WeatherModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: WeatherModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: WeatherModel.CodingKeys._displayState)
        try container.encode(self.weatherUpdate, forKey: WeatherModel.CodingKeys._weatherUpdate_)
        try container.encode(self.time, forKey: WeatherModel.CodingKeys._time)
        try container.encode(self.cloudThickness, forKey: WeatherModel.CodingKeys._cloudThickness)
        try container.encode(self.stormType, forKey: WeatherModel.CodingKeys._stormType)
        try container.encode(self.rainAngle, forKey: WeatherModel.CodingKeys._rainAngle)
        try container.encode(self.rainIntensity, forKey: WeatherModel.CodingKeys._rainIntensity)
        try container.encode(self.lightningFrequency, forKey: WeatherModel.CodingKeys._lightningFrequency)
        try container.encode(self.lightningMaxBolts, forKey: WeatherModel.CodingKeys._lightningMaxBolts)
        try container.encode(self.lightningForkProbability, forKey: WeatherModel.CodingKeys._lightningForkProbability)
        try container.encodeIfPresent(self.photoId, forKey: WeatherModel.CodingKeys._photoId)
    }
}
