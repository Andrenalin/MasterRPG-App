// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class WeatherDataModel {
    public init(itemId: UUID = UUID(), photoId: UUID? = nil, time: Double = 0, cloudThickness: Cloud.Thickness = Cloud.Thickness.none, stormType: Storm.Contents = Storm.Contents.none, rainAngle: Double = 0, rainIntensity: Double = 0, lightningFrequency: Double = 0, lightningMaxBolts: Double = 0, lightningForkProbability: Double = 0) {
        self.itemId = itemId
        self.displayState = 0
        
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
    
    @Attribute(.preserveValueOnDeletion)
    public var itemId: UUID = UUID()
    public var displayState: Int = 0

    var photoId: UUID? = nil

    var time: Double = 0
    
    var cloudThickness: Cloud.Thickness = Cloud.Thickness.none

    var stormType: Storm.Contents = Storm.Contents.none
    var rainAngle: Double = 0
    var rainIntensity: Double = 0

    var lightningFrequency: Double = 0
    var lightningMaxBolts: Double = 0
    var lightningForkProbability: Double = 0
    
    //@CodableIgnored
    var rainDirection: Bool {
        get { rainAngle >= 0 }
        set { rainAngle *= -1 }
    }
    
    // MARK: Codable
    struct WeatherDataModelCodable: Equatable, Hashable, Codable, Sendable {
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
    }
    
    convenience init(_ model: WeatherDataModelCodable) {
        self.init(itemId: model.itemId, photoId: model.photoId, time: model.time, cloudThickness: model.cloudThickness, stormType: model.stormType, rainAngle: model.rainAngle, rainIntensity: model.rainIntensity, lightningFrequency: model.lightningFrequency, lightningMaxBolts: model.lightningMaxBolts, lightningForkProbability: model.lightningForkProbability)
    }
    
    var codableModel: WeatherDataModelCodable {
        WeatherDataModelCodable(
            itemId: itemId,
            photoId: photoId,
            time: time,
            cloudThickness: cloudThickness,
            stormType: stormType,
            rainAngle: rainAngle,
            rainIntensity: rainIntensity,
            lightningFrequency: lightningFrequency,
            lightningMaxBolts: lightningMaxBolts,
            lightningForkProbability: lightningForkProbability
        )
    }
    
    func replace(_ model: WeatherDataModelCodable) {
        itemId = model.itemId
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
    
    func duplicate(newItemId: UUID) -> WeatherDataModel {
        WeatherDataModel(
            itemId: newItemId,
            photoId: photoId,
            time: time,
            cloudThickness: cloudThickness,
            stormType: stormType,
            rainAngle: rainAngle,
            rainIntensity: rainIntensity,
            lightningFrequency: lightningFrequency,
            lightningMaxBolts: lightningMaxBolts,
            lightningForkProbability: lightningForkProbability
        )
    }
}

extension WeatherDataModel: ModelCachable {
    public static func newModel(for itemId: UUID) -> WeatherDataModel {
        WeatherDataModel(itemId: itemId)
    }
}
