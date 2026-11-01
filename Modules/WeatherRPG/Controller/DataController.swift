// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
            self.dataController = CoreDataController<WeatherModel, RPGWeather>(context: context, relationshipKeyPaths: ["entries"])
            self.token = token
        }
        
        let dataController: CoreDataController<WeatherModel, RPGWeather>
        let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGWeather, token: String) -> WeatherSnapshot {
        WeatherSnapshot(
            id: repairedUuid(of: model, at: \.uuid),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.weatherCategory ?? "", defaultValue: ItemListCategory.adventure),
            displayState: Int(model.displayState),
            weatherUpdate: CRDT(string: model.weatherUpdate ?? "", defaultValue: UUID()),
            time: WeatherLimits.clamped(Double(model.time), to: WeatherLimits.time),
            cloudThickness: Cloud.Thickness(rawValue: Int(model.cloudThickness)) ?? .none,
            stormType: Storm.Contents(rawValue: Int(model.stormType)) ?? .none,
            rainAngle: WeatherLimits.clamped(Double(model.rainAngle), to: WeatherLimits.rainAngle),
            rainIntensity: WeatherLimits.clamped(Double(model.rainIntensity), to: WeatherLimits.rainIntensity),
            lightningFrequency: WeatherLimits.clamped(Double(model.lightningFrequency), to: WeatherLimits.lightningFrequency),
            lightningMaxBolts: WeatherLimits.clamped(Double(model.lightningMaxBolts), to: WeatherLimits.lightningMaxBolts),
            lightningForkProbability: WeatherLimits.clamped(Double(model.lightningForkProbability), to: WeatherLimits.lightningForkProbability),
            photoId: model.photoUUID,
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // MARK: snapshot -> managed object (context queue)

    @Sendable
    func applySnapshot(_ snapshot: WeatherSnapshot, into model: RPGWeather) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.weatherCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(clamping: snapshot.displayState)
        model.weatherUpdate <=> snapshot.weatherUpdate.rawValue
        model.time <=> Float(snapshot.time)
        model.cloudThickness <=> Int16(snapshot.cloudThickness.rawValue)
        model.stormType <=> Int16(snapshot.stormType.rawValue)
        model.rainAngle <=> Float(snapshot.rainAngle)
        model.rainIntensity <=> Float(snapshot.rainIntensity)
        model.lightningFrequency <=> Float(snapshot.lightningFrequency)
        model.lightningMaxBolts <=> Float(snapshot.lightningMaxBolts)
        model.lightningForkProbability <=> Float(snapshot.lightningForkProbability)
        model.photoUUID <=> snapshot.photoId
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries.$update.rawValue) {
            model.entriesModel = model.syncEntries(
                incoming: snapshot.entries.wrappedValue,
                current: model.entriesModel,
                childId: { $0.id },
                map: { self.map($0, into: $1, index: $2) }
            )
        }
        model.parentId <=> snapshot.parentId
    }
    

    // MARK: model <-> snapshot (MainActor)

    @MainActor
    func makeModel(from snapshot: WeatherSnapshot) -> WeatherModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: WeatherModel) -> WeatherSnapshot {
        WeatherSnapshot(model)
    }

    // MARK: - ChildEntryViewModel

    private func map(_ model: RPGWeatherEntry) -> ChildEntryModel {
        ChildEntryModel(
            id: repairedUuid(of: model, at: \.uuid),
            childId: (model.childUUID ?? repairedUuid(of: model, at: \.uuid))
        )
    }

    private func map(_ viewModel: ChildEntryModel, into entry: RPGWeatherEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.childUUID = viewModel.childId
        entry.index = Int16(clamping: index)
    }
}
