// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
        // Prefetch entries: mapViewModel touches entriesModel on every fetched object,
        // which fires one relationship fault per row without prefetching.
        self.dataController = CoreDataController<AudioModel, RPGAudio>(context: context, batchContext: batchContext, relationshipKeyPaths: ["entries"])
        self.token = token
    }

    let dataController: CoreDataController<AudioModel, RPGAudio>
    let token: String
}

extension DataController: CoreDataPersistable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGAudio, token: String) -> AudioModel {
        AudioModel(
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

    // MARK: viewmodel -> model
    
    func mapModel(_ viewModel: AudioModel, into model: RPGAudio) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.audioCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        unequalSet(lhs: &model.fileUrlUpdate, rhs: viewModel.fileUrl_.$update.rawValue) {
            model.fileUrl = viewModel.fileUrl?.rawValue ?? ""
        }
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            let oldEntries = model.entriesModel
            let newEntries = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
            model.entriesModel = newEntries
            // The inverse rule is Nullify, so entries dropped from the relationship
            // would remain as orphaned rows (locally and in CloudKit) — delete them.
            let keptEntries = Set(newEntries.map(ObjectIdentifier.init))
            for entry in oldEntries where !keptEntries.contains(ObjectIdentifier(entry)) {
                model.managedObjectContext?.delete(entry)
            }
        }
        model.parentId <=> viewModel.parentId
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
