// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData
internal import CoreGraphics

struct DataController: Sendable {
    @MainActor
    init(root: PdfRoot, context: NSManagedObjectContext, token: String) {
        self.root = root
        self.changeObserver = CoreDataChangeObserver()
        self.dataController = CoreDataController<PdfModel, RPGPdf>(context: context)
        self.token = token

        changeObserver.observeCoreDataChanges(from: context, entity: RPGPdf.entity(), handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }
    
    weak var root: PdfRoot!
    let dataController: CoreDataController<PdfModel, RPGPdf>
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

    func mapViewModel(_ model: RPGPdf, token: String) -> PdfModel {
        PdfModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.pdfCategory ?? "", defaultValue: ItemListCategory.rules),
            displayState: Int(model.displayState),
            fileUrl: CRDTDataUpdate(wrappedValue: FileUrl(string: model.fileUrl ?? "", fileId: model.uuid ?? UUID(), module: token, unconvertedData: nil), update: CRDT(string: model.fileUrlUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID()))
        )
    }
    
    // MARK: viewmodel -> model

    func mapModel(_ viewModel: PdfModel, into model: RPGPdf) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.pdfCategory <=> viewModel.category_.rawValue
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

    // MARK: - PdfEntryViewModel

    private func map(_ model: RPGPdfEntry) -> PdfEntryModel {
        PdfEntryModel(
            id: model.uuid ?? UUID(),
            name: model.name ?? "",
            content: model.content ?? "",
            pageNumber: model.pageLabel ?? "",
            bounds: JSONString.decode(text: model.bounds) ?? .zero
        )
    }

    private func map(_ viewModel: PdfEntryModel, into entry: RPGPdfEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.name = viewModel.name
        entry.content = viewModel.content
        entry.pageLabel = viewModel.pageLabel
        entry.index = Int16(index)
        entry.bounds = JSONString.encode(value: viewModel.bounds) ?? ""
    }
}

