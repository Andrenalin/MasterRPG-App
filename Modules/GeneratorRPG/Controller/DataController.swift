// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
            self.dataController = CoreDataController<GeneratorModel, RPGGenerator>(context: context)
            self.token = token
        }
        
        let dataController: CoreDataController<GeneratorModel, RPGGenerator>
        let token: String
}

extension DataController: CoreDataPersistable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGGenerator, token: String) -> GeneratorModel {
        GeneratorModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.generatorCategory ?? "", defaultValue: ItemListCategory.item),
            displayState: Int(model.displayState),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId,
            genType: GeneratorModel.GenType(rawValue: Int(model.genType)) ?? .adventure,
            referenceId: model.referenceId
        )
    }

    // MARK: viewmodel -> model
    
    func mapModel(_ viewModel: GeneratorModel, into model: RPGGenerator) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.generatorCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            model.entriesModel = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
        model.parentId <=> viewModel.parentId
        model.genType <=> Int16(viewModel.genType.rawValue)
        model.referenceId <=> viewModel.referenceId
    }
    
    // MARK: - ChildEntryViewModel

    private func map(_ model: RPGGeneratorEntry) -> ChildEntryModel {
        ChildEntryModel(
            id: model.uuid ?? UUID(),
            childId: (model.childUUID ?? model.uuid ?? UUID())
        )
    }

    private func map(_ viewModel: ChildEntryModel, into entry: RPGGeneratorEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.childUUID = viewModel.childId
        entry.index = Int16(index)
    }
}
