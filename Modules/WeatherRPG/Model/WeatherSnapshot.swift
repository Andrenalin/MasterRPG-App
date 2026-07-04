// @copyright André Trettin

import CoreRPG
import Foundation

/// Sendable value snapshot of a WeatherModel — the only representation that crosses
/// the Core Data context boundary. Not Codable: the .gmz wire format stays on
/// WeatherModel's Codable implementation.
struct WeatherSnapshot: Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let weatherUpdate: CRDT<UUID>
    let time: Double
    let cloudThickness: Cloud.Thickness
    let stormType: Storm.Contents
    let rainAngle: Double
    let rainIntensity: Double
    let lightningFrequency: Double
    let lightningMaxBolts: Double
    let lightningForkProbability: Double
    let photoId: UUID?
    let entries: CRDTDataUpdate<[ChildEntryModel]>
    let parentId: UUID?
}

extension WeatherSnapshot {
    @MainActor
    init(_ model: WeatherModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        weatherUpdate = model.weatherUpdate_
        time = model.time
        cloudThickness = model.cloudThickness
        stormType = model.stormType
        rainAngle = model.rainAngle
        rainIntensity = model.rainIntensity
        lightningFrequency = model.lightningFrequency
        lightningMaxBolts = model.lightningMaxBolts
        lightningForkProbability = model.lightningForkProbability
        photoId = model.photoId
        entries = model.entries_
        parentId = model.parentId
    }

    @MainActor
    func makeModel() -> WeatherModel {
        WeatherModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            weatherUpdate: weatherUpdate,
            time: time,
            cloudThickness: cloudThickness,
            stormType: stormType,
            rainAngle: rainAngle,
            rainIntensity: rainIntensity,
            lightningFrequency: lightningFrequency,
            lightningMaxBolts: lightningMaxBolts,
            lightningForkProbability: lightningForkProbability,
            photoId: photoId,
            entries: entries,
            parentId: parentId
        )
    }
}
