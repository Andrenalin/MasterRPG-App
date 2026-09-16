// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
        self.dataController = CoreDataController<ValueModel, RPGValue>(context: context, relationshipKeyPaths: ["entries", "photos"])
        self.token = token
    }
    
    let dataController: CoreDataController<ValueModel, RPGValue>
    let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)
    
    @Sendable
    func mapSnapshot(_ model: RPGValue, token: String) -> ValueSnapshot {
        ValueSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.valueCategory ?? "", defaultValue: ItemListCategory.game),
            displayState: Int(model.displayState),
            photoId: CRDT(string: model.photoUUID ?? "", defaultValue: nil),
            photos: CRDTDataUpdate(wrappedValue: model.photoIds.compactMap { $0.uuid }, update: CRDT(string: model.photosUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentUUID,
            diceId: model.diceUUID,
            groupId: model.groupUUID
        )
    }
    
    // MARK: snapshot -> managed object (context queue)
    
    @Sendable
    func applySnapshot(_ snapshot: ValueSnapshot, into model: RPGValue) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.valueCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        model.photoUUID <=> snapshot.photoId.rawValue
        unequalSet(lhs: &model.photosUpdate, rhs: snapshot.photos.$update.rawValue) {
            model.photoIds = model.syncEntries(
                incoming: snapshot.photos.wrappedValue,
                current: model.photoIds,
                childId: { $0 },
                map: { uuid, entry, index in
                    entry.uuid = uuid
                    entry.index = Int16(index)
                }
            )
        }
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries.$update.rawValue) {
            model.entriesModel = model.syncEntries(
                incoming: snapshot.entries.wrappedValue,
                current: model.entriesModel,
                childId: { $0.id },
                map: { self.map($0, into: $1, index: $2) }
            )
        }
        model.parentUUID <=> snapshot.parentId
        model.diceUUID <=> snapshot.diceId
        model.groupUUID <=> snapshot.groupId
    }
    

    // MARK: model <-> snapshot (MainActor)

    @MainActor
    func makeModel(from snapshot: ValueSnapshot) -> ValueModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: ValueModel) -> ValueSnapshot {
        ValueSnapshot(model)
    }

    // MARK: - ValueEntryModel
    
    private func map(_ model: [RPGValueEntry]) -> [ValueEntryModel] {
        model.sorted { $0.index < $1.index }.map { map($0) }
    }
    
    private func map(_ model: RPGValueEntry) -> ValueEntryModel {
        ValueEntryModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            type: CRDT(string: model.type ?? "", defaultValue: ValueEntryModel.ValueType.text),
            isGenerator: CRDT(string: model.isGenerator ?? "", defaultValue: false),
            value: CRDT(wrappedValue: model.value ?? ""),
            diceId: CRDT(string: model.diceUUID ?? "", defaultValue: nil),
            valueId: CRDT(string: model.valueUUID ?? "", defaultValue: nil)
        )
    }
    
    private func map(_ viewModel: ValueEntryModel, into valueEntry: RPGValueEntry, index: Int) {
        valueEntry.uuid <=> viewModel.id
        valueEntry.name <=> viewModel.$name.rawValue
        valueEntry.type <=> viewModel.$type.rawValue
        valueEntry.isGenerator <=> viewModel.$isGenerator.rawValue
        valueEntry.value <=> viewModel.$value.rawValue
        valueEntry.index <=> Int16(index)
        valueEntry.diceUUID <=> viewModel.$diceId.rawValue
        valueEntry.valueUUID <=> viewModel.$valueId.rawValue
    }
}
