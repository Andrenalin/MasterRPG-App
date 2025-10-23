// @copyright André Trettin

import AndrenalinKit
import CoreData
import Foundation

struct DataController: Sendable {
    @MainActor
    init(root: AudioRoot, context: NSManagedObjectContext, token: String) {
        self.root = root
        self.changeObserver = CoreDataChangeObserver()
        self.dataController = CoreDataController<AudioModel, RPGAudio>(context: context)
        self.token = token

        changeObserver.observeCoreDataChanges(from: context, entity: RPGAudio.entity(), handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }
    
    weak var root: AudioRoot!
    let dataController: CoreDataController<AudioModel, RPGAudio>
    var itemControllable: any ItemControllable {
        root.itemController
    }
    let changeObserver: CoreDataChangeObserver
    let token: String
}

extension DataController: CoreDataPersistable, DataPersistenceControllable, SyncDataControllable {
    var dataControllable: any CoreDataPersistable {
        self
    }
    
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
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID()))
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
            model.entriesModel = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
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
