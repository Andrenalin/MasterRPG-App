// @copyright André Trettin

import CoreRPG
import Foundation

struct WeatherModel: Identifiable, Codable {
    init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .scenario, displayState: Int = 0, weatherUpdate: UUID = UUID(), time: Double = 0, cloudThickness: Cloud.Thickness = .none, stormType: Storm.Contents = .none, rainAngle: Double = 0, rainIntensity: Double = 0, lightningFrequency: Double = 0, lightningMaxBolts: Double = 0, lightningForkProbability: Double = 0, photoId: UUID? = nil) {
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
    var name: String = ""
    var description: String = ""
    var tags: [String] = []
    var category: ItemListCategory = .scenario
    var displayState: Int = 0
    var weatherUpdate: UUID = UUID()
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
}
