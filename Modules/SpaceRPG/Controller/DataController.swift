// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
            self.dataController = CoreDataController<SpaceModel, RPGSpace>(context: context, batchContext: batchContext, relationshipKeyPaths: ["entries"])
            self.token = token
        }
        
        let dataController: CoreDataController<SpaceModel, RPGSpace>
        let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGSpace, token: String) -> SpaceSnapshot {
        SpaceSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.spaceCategory ?? "", defaultValue: ItemListCategory.item),
            displayState: Int(model.displayState),
            degrees: CRDT(string: model.degrees ?? "", defaultValue: 0.0),
            fileUrl: CRDTDataUpdate(wrappedValue: FileUrl(string: model.fileUrl ?? "", fileId: model.uuid ?? UUID(), module: token, unconvertedData: nil), update: CRDT(string: model.fileUrlUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // MARK: snapshot -> managed object (context queue)

    @Sendable
    func applySnapshot(_ snapshot: SpaceSnapshot, into model: RPGSpace) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.spaceCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        model.degrees <=> snapshot.degrees.rawValue
        unequalSet(lhs: &model.fileUrlUpdate, rhs: snapshot.fileUrl.$update.rawValue) {
            model.fileUrl = snapshot.fileUrl.wrappedValue?.rawValue ?? ""
        }
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
    func makeModel(from snapshot: SpaceSnapshot) -> SpaceModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: SpaceModel) -> SpaceSnapshot {
        SpaceSnapshot(model)
    }

    // MARK: - SpaceEntryViewModel

    private func map(_ model: RPGSpaceEntry) -> SpaceEntryModel {
        SpaceEntryModel(
            id: model.uuid ?? UUID(),
            spaceId: (model.spaceUUID ?? model.uuid ?? UUID())
        )
    }

    private func map(_ viewModel: SpaceEntryModel, into entry: RPGSpaceEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.spaceUUID = viewModel.spaceId
        entry.index = Int16(index)
    }
}
