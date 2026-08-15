// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
        // Prefetch entries: mapSnapshot touches entriesModel on every fetched object,
        // which fires one relationship fault per row without prefetching.
        self.dataController = CoreDataController<AudioModel, RPGAudio>(context: context, batchContext: batchContext, relationshipKeyPaths: ["entries"])
        self.token = token
    }

    let dataController: CoreDataController<AudioModel, RPGAudio>
    let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGAudio, token: String) -> AudioSnapshot {
        AudioSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.audioCategory ?? "", defaultValue: ItemListCategory.music),
            displayState: Int(model.displayState),
            fileUrl: CRDTDataUpdate(wrappedValue: FileUrl(string: model.fileUrl ?? "", fileId: model.uuid ?? UUID(), module: token, unconvertedData: nil), update: CRDT(string: model.fileUrlUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // MARK: snapshot -> managed object (context queue)

    @Sendable
    func applySnapshot(_ snapshot: AudioSnapshot, into model: RPGAudio) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.audioCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
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
    func makeModel(from snapshot: AudioSnapshot) -> AudioModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: AudioModel) -> AudioSnapshot {
        AudioSnapshot(model)
    }

    // MARK: - AudioEntryViewModel

    private func map(_ model: RPGAudioEntry) -> AudioEntryModel {
        AudioEntryModel(
            id: model.uuid ?? UUID(),
            audioId: (model.audioUUID ?? model.uuid ?? UUID())
        )
    }

    private func map(_ viewModel: AudioEntryModel, into entry: RPGAudioEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.audioUUID = viewModel.audioId
        entry.index = Int16(index)
    }
}
