// @copyright André Trettin

import CoreRPG
import Foundation

extension WeatherModel {
    /// The editor window's forced save during a game: the weather settings and photo it changed
    /// reach the library too. See `ItemDataAccessible.applyEdit(from:to:)`.
    public func applyModuleEdit(from base: WeatherModel, to edited: WeatherModel) {
        if base.weatherUpdate_.wrappedValue != edited.weatherUpdate_.wrappedValue { weatherUpdate_ = edited.weatherUpdate_ }
        if base.time != edited.time { time = edited.time }
        if base.cloudThickness != edited.cloudThickness { cloudThickness = edited.cloudThickness }
        if base.stormType != edited.stormType { stormType = edited.stormType }
        if base.rainAngle != edited.rainAngle { rainAngle = edited.rainAngle }
        if base.rainIntensity != edited.rainIntensity { rainIntensity = edited.rainIntensity }
        if base.lightningFrequency != edited.lightningFrequency { lightningFrequency = edited.lightningFrequency }
        if base.lightningMaxBolts != edited.lightningMaxBolts { lightningMaxBolts = edited.lightningMaxBolts }
        if base.lightningForkProbability != edited.lightningForkProbability { lightningForkProbability = edited.lightningForkProbability }
        if base.photoId != edited.photoId { photoId = edited.photoId }
    }
}
