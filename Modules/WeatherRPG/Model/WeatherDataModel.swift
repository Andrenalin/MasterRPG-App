// @copyright André Trettin

import Foundation
import SwiftData

@Model
final class WeatherDataModel {
    init(itemId: UUID = UUID(), photoId: UUID? = nil, time: Double = 0, cloudThickness: Cloud.Thickness = Cloud.Thickness.none, stormType: Storm.Contents = Storm.Contents.none, rainAngle: Double = 0, rainIntensity: Double = 0, lightningFrequency: Double = 0, lightningMaxBolts: Double = 0, lightningForkProbability: Double = 0) {
        self.itemId = itemId
        self.photoId = photoId
        self.time = time
        self.cloudThickness = cloudThickness
        self.stormType = stormType
        self.rainAngle = rainAngle
        self.rainIntensity = rainIntensity
        self.lightningFrequency = lightningFrequency
        self.lightningMaxBolts = lightningMaxBolts
        self.lightningForkProbability = lightningForkProbability
    }
    
    var itemId: UUID = UUID()
    var photoId: UUID? = nil

    var time: Double = 0
    var cloudThickness: Cloud.Thickness = Cloud.Thickness.none

    var stormType: Storm.Contents = Storm.Contents.none
    var rainAngle: Double = 0
    var rainIntensity: Double = 0

    var lightningFrequency: Double = 0
    var lightningMaxBolts: Double = 0
    var lightningForkProbability: Double = 0
    
    var rainDirection: Bool {
        get { rainAngle >= 0 }
        set { rainAngle *= -1 }
    }
}
