// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData
import CoreGraphics
import os.log

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
            self.dataController = CoreDataController<PdfModel, RPGPdf>(context: context, relationshipKeyPaths: ["entries"])
            self.token = token
        }
        
        let dataController: CoreDataController<PdfModel, RPGPdf>
        let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGPdf, token: String) -> PdfSnapshot {
        let id = repairedUuid(for: model)
        return PdfSnapshot(
            id: id,
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.pdfCategory ?? "", defaultValue: ItemListCategory.rules),
            displayState: Int(model.displayState),
            fileUrl: CRDTDataUpdate(wrappedValue: FileUrl(string: model.fileUrl ?? "", fileId: id, module: token, unconvertedData: nil), update: CRDT(string: model.fileUrlUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // A nil `uuid` is expected transiently under CloudKit sync (attributes must be
    // optional), but must never be silently re-randomized on every map call — that
    // makes the same managed object resolve to a different domain id on separate
    // passes. Assign and persist a stable id once instead. See CODE_AUDIT_Pdf §5.4.
    @Sendable
    private func repairedUuid(for model: RPGPdf) -> UUID {
        if let uuid = model.uuid { return uuid }
        let id = UUID()
        Logger.itemController.error("RPGPdf managed object had a nil uuid; assigning and persisting \(id, privacy: .public) to repair identity.")
        model.uuid = id
        return id
    }

    @Sendable
    private func repairedUuid(for model: RPGPdfEntry) -> UUID {
        if let uuid = model.uuid { return uuid }
        let id = UUID()
        Logger.itemController.error("RPGPdfEntry managed object had a nil uuid; assigning and persisting \(id, privacy: .public) to repair identity.")
        model.uuid = id
        return id
    }
    
    // MARK: snapshot -> managed object (context queue)

    @Sendable
    func applySnapshot(_ snapshot: PdfSnapshot, into model: RPGPdf) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.pdfCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(clamping: snapshot.displayState)
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
    func makeModel(from snapshot: PdfSnapshot) -> PdfModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: PdfModel) -> PdfSnapshot {
        PdfSnapshot(model)
    }

    // MARK: - PdfEntryViewModel

    private func map(_ model: RPGPdfEntry) -> PdfEntryModel {
        PdfEntryModel(
            id: repairedUuid(for: model),
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
        entry.index = Int16(clamping: index)
        entry.bounds = JSONString.encode(value: viewModel.bounds) ?? ""
    }
}

