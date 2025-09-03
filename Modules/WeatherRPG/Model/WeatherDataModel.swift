// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
public final class WeatherDataModel {
    public init(itemId: UUID = UUID(), photoId: UUID? = nil, time: Double = 0, cloudThickness: Cloud.Thickness = Cloud.Thickness.none, stormType: Storm.Contents = Storm.Contents.none, rainAngle: Double = 0, rainIntensity: Double = 0, lightningFrequency: Double = 0, lightningMaxBolts: Double = 0, lightningForkProbability: Double = 0) {
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
    
    @CodableIgnored
    var cloudThickness: Cloud.Thickness = Cloud.Thickness.none

    @CodableIgnored
    var stormType: Storm.Contents = Storm.Contents.none
    var rainAngle: Double = 0
    var rainIntensity: Double = 0

    var lightningFrequency: Double = 0
    var lightningMaxBolts: Double = 0
    var lightningForkProbability: Double = 0
    
    @CodableIgnored
    var rainDirection: Bool {
        get { rainAngle >= 0 }
        set { rainAngle *= -1 }
    }
}

// MARK: - Conversion methods for Version2024 compatibility
extension WeatherDataModel {
    convenience init(_ model: WeatherModel) {
        self.init(
            itemId: model.id,
            photoId: model.photoId,
            time: model.time,
            cloudThickness: model.cloudThickness,
            stormType: model.stormType,
            rainAngle: model.rainAngle,
            rainIntensity: model.rainIntensity,
            lightningFrequency: model.lightningFrequency,
            lightningMaxBolts: model.lightningMaxBolts,
            lightningForkProbability: model.lightningForkProbability
        )
    }
    
    var weatherModel: WeatherModel {
        WeatherModel(
            id: itemId,
            time: time,
            cloudThickness: cloudThickness,
            stormType: stormType,
            rainAngle: rainAngle,
            rainIntensity: rainIntensity,
            lightningFrequency: lightningFrequency,
            lightningMaxBolts: lightningMaxBolts,
            lightningForkProbability: lightningForkProbability,
            photoId: photoId
        )
    }
    
    func replace(_ model: WeatherModel) {
        photoId = model.photoId
        time = model.time
        cloudThickness = model.cloudThickness
        stormType = model.stormType
        rainAngle = model.rainAngle
        rainIntensity = model.rainIntensity
        lightningFrequency = model.lightningFrequency
        lightningMaxBolts = model.lightningMaxBolts
        lightningForkProbability = model.lightningForkProbability
    }
}
