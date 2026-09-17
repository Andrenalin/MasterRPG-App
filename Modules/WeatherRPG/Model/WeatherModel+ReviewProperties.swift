// @copyright André Trettin

import CoreRPG
import Foundation

extension WeatherModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: String(localized: "Photo", bundle: .module)) {
                ReviewPropertyValue(photoId: ($0 as? WeatherModel)?.photoId)
            },
            ReviewCustomProperty(displayName: String(localized: "Time", bundle: .module)) {
                ReviewPropertyValue(($0 as? WeatherModel)?.time ?? 0)
            },
            ReviewCustomProperty(displayName: String(localized: "Clouds", bundle: .module)) {
                let thickness = ($0 as? WeatherModel)?.cloudThickness ?? .none
                return .option(String(localized: thickness.localizedTitle))
            },
            ReviewCustomProperty(displayName: String(localized: "Storm", bundle: .module)) {
                let contents = ($0 as? WeatherModel)?.stormType ?? .none
                return .option(String(localized: contents.localizedTitle))
            },
            ReviewCustomProperty(displayName: String(localized: "Rain Angle", bundle: .module)) {
                ReviewPropertyValue(($0 as? WeatherModel)?.rainAngle ?? 0)
            },
            ReviewCustomProperty(displayName: String(localized: "Rain Intensity", bundle: .module)) {
                ReviewPropertyValue(($0 as? WeatherModel)?.rainIntensity ?? 0)
            },
            ReviewCustomProperty(displayName: String(localized: "Lightning Frequency", bundle: .module)) {
                ReviewPropertyValue(($0 as? WeatherModel)?.lightningFrequency ?? 0)
            },
            ReviewCustomProperty(displayName: String(localized: "Lightning Max Bolts", bundle: .module)) {
                ReviewPropertyValue(($0 as? WeatherModel)?.lightningMaxBolts ?? 0)
            },
            ReviewCustomProperty(displayName: String(localized: "Lightning Fork Probability", bundle: .module)) {
                ReviewPropertyValue(($0 as? WeatherModel)?.lightningForkProbability ?? 0)
            }
        ]
    }
}
