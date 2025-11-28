// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
        self.dataController = CoreDataController<AdventureModel, RPGAdventure>(context: context)
        self.token = token
    }
    
    let dataController: CoreDataController<AdventureModel, RPGAdventure>
    let token: String
}

extension DataController: CoreDataPersistable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGAdventure, token: String) -> AdventureModel {
        let vm = AdventureModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.adventureCategory ?? "", defaultValue: ItemListCategory(rawValue: Int(model.adventureCategory ?? "1000") ?? 1000) ?? ItemListCategory.adventure),
            displayState: Int(model.displayState),
            photoId: CRDT(string: model.photoUUID ?? "", defaultValue: nil),
            entries: CRDTDataUpdate(wrappedValue: map(model.entriesModel), update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID()))
        )
        return vm
    }

    // MARK: viewmodel -> model

    func mapModel(_ viewModel: AdventureModel, into model: RPGAdventure) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.adventureCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        model.photoUUID <=> viewModel.photoId_.rawValue
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            model.entriesModel = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
    }

    // MARK: - EntryViewModel

    private func map(_ model: [RPGAdventureEntry]) -> [AdventureEntryModel] {
        model.sorted { $0.index < $1.index }.map { map($0) }
    }

    private func map(_ model: RPGAdventureEntry) -> AdventureEntryModel {
        AdventureEntryModel(
            id: model.uuid ?? UUID(),
            name: CRDT(string: model.name ?? "", defaultValue: ""),
            content: CRDT(string: model.content ?? "", defaultValue: ""),
            displayState: 0
        )
    }

    private func map(_ viewModel: AdventureEntryModel, into model: RPGAdventureEntry, index: Int) {
        model.uuid = viewModel.id
        model.name = viewModel.$name.rawValue
        model.content = viewModel.$content.rawValue
        model.index = Int16(index)
    }
}
