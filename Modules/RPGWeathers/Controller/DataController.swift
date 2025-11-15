// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
            self.dataController = CoreDataController<WeatherModel, RPGWeather>(context: context)
            self.token = token
        }
        
        let dataController: CoreDataController<WeatherModel, RPGWeather>
        let token: String
}

extension DataController: CoreDataPersistable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGWeather, token: String) -> WeatherModel {
        WeatherModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.weatherCategory ?? "", defaultValue: ItemListCategory.adventure),
            displayState: Int(model.displayState),
            weatherUpdate: CRDT(string: model.weatherUpdate ?? "", defaultValue: UUID()),
            time: Double(model.time),
            cloudThickness: Cloud.Thickness(rawValue: Int(model.cloudThickness)) ?? .none,
            stormType: Storm.Contents(rawValue: Int(model.stormType)) ?? .none,
            rainAngle: Double(model.rainAngle),
            rainIntensity: Double(model.rainIntensity),
            lightningFrequency: Double(model.lightningFrequency),
            lightningMaxBolts: Double(model.lightningMaxBolts),
            lightningForkProbability: Double(model.lightningForkProbability),
            photoId: model.photoUUID,
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // MARK: viewmodel -> model

    func mapModel(_ viewModel: WeatherModel, into model: RPGWeather) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.weatherCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        model.weatherUpdate <=> viewModel.weatherUpdate_.rawValue
        model.time <=> Float(viewModel.time)
        model.cloudThickness <=> Int16(viewModel.cloudThickness.rawValue)
        model.stormType <=> Int16(viewModel.stormType.rawValue)
        model.rainAngle <=> Float(viewModel.rainAngle)
        model.rainIntensity <=> Float(viewModel.rainIntensity)
        model.lightningFrequency <=> Float(viewModel.lightningFrequency)
        model.lightningMaxBolts <=> Float(viewModel.lightningMaxBolts)
        model.lightningForkProbability <=> Float(viewModel.lightningForkProbability)
        model.photoUUID <=> viewModel.photoId
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            model.entriesModel = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
        model.parentId <=> viewModel.parentId
    }
    
    // MARK: - ChildEntryViewModel

    private func map(_ model: RPGWeatherEntry) -> ChildEntryModel {
        ChildEntryModel(
            id: model.uuid ?? UUID(),
            childId: (model.childUUID ?? model.uuid ?? UUID())
        )
    }

    private func map(_ viewModel: ChildEntryModel, into entry: RPGWeatherEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.childUUID = viewModel.childId
        entry.index = Int16(index)
    }
}
