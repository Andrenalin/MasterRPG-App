// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
            self.dataController = CoreDataController<GeneratorModel, RPGGenerator>(context: context, batchContext: batchContext)
            self.token = token
        }
        
        let dataController: CoreDataController<GeneratorModel, RPGGenerator>
        let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGGenerator, token: String) -> GeneratorSnapshot {
        GeneratorSnapshot(
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

    // MARK: snapshot -> managed object (context queue)
    
    @Sendable
    func applySnapshot(_ snapshot: GeneratorSnapshot, into model: RPGGenerator) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.generatorCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries.$update.rawValue) {
            model.entriesModel = snapshot.entries.wrappedValue.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
        model.parentId <=> snapshot.parentId
        model.genType <=> Int16(snapshot.genType.rawValue)
        model.referenceId <=> snapshot.referenceId
    }
    

    // MARK: model <-> snapshot (MainActor)

    @MainActor
    func makeModel(from snapshot: GeneratorSnapshot) -> GeneratorModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: GeneratorModel) -> GeneratorSnapshot {
        GeneratorSnapshot(model)
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
