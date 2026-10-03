// @copyright André Trettin

import CoreRPG
import Foundation

extension WeatherModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: WeatherModel) -> WeatherModel {
        return assumeMainActorIsolated {
            let merged = weatherUpdate_.merged(other: other.weatherUpdate_)
            let shouldUpdate = merged.wrappedValue == weatherUpdate_.wrappedValue
            let mergedCategory = category_.merged(other: other.category_)
            // Folders union their members, other categories last-writer-wins. See CODE_AUDIT_Folder §9.8.
            let mergedEntries = FolderEntryMerge.mergedEntries(category: mergedCategory.wrappedValue, local: entries_, remote: other.entries_, id: \.id, name: \.name, childId: \.childId)
            return WeatherModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
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
                entries: mergedEntries,
                parentId: other.parentId
            )

        }
    }

    nonisolated public func isSame(_ other: WeatherModel) -> Bool {
        return assumeMainActorIsolated {
            // Split comparison into typed chunks for faster type-checking
            let basicFieldsMatch: Bool = (
                name == other.name &&
                description == other.description &&
                tags == other.tags &&
                category == other.category
            )
            guard basicFieldsMatch else { return false }

            let weatherConfigMatch: Bool = (
                weatherUpdate_.wrappedValue == other.weatherUpdate_.wrappedValue &&
                time == other.time &&
                cloudThickness == other.cloudThickness &&
                stormType == other.stormType
            )
            guard weatherConfigMatch else { return false }

            let rainConfigMatch: Bool = (
                rainAngle == other.rainAngle &&
                rainIntensity == other.rainIntensity
            )
            guard rainConfigMatch else { return false }

            let lightningConfigMatch: Bool = (
                lightningFrequency == other.lightningFrequency &&
                lightningMaxBolts == other.lightningMaxBolts &&
                lightningForkProbability == other.lightningForkProbability
            )
            guard lightningConfigMatch else { return false }

            return photoId == other.photoId &&
                   entries_.update == other.entries_.update &&
                   parentId == other.parentId

        }
    }
}
