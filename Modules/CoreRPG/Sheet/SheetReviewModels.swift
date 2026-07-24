// @copyright André Trettin

import Foundation
import SwiftUI

struct SheetReviewEntryID: Hashable {
    let itemID: UUID
    let entryID: UUID
}

struct SheetReviewVersionID: Hashable {
    let itemID: UUID
    let entryID: UUID
    let decision: SingleReviewDecision
}

@MainActor
struct SheetReviewVersion: Identifiable {
    let id: SheetReviewVersionID
    let decision: SingleReviewDecision
    let sheetModel: SheetModel?
    let entry: (any EntryDataAccessable)?

    var isAvailable: Bool {
        sheetModel != nil && entry != nil
    }
}

@Observable @MainActor
final class SheetEntryReviewModel: Identifiable {
    init(
        itemID: UUID,
        entryModel: SingleEntryImportModel,
        versions: [SheetReviewVersion],
        isExpanded: Bool = false
    ) {
        id = SheetReviewEntryID(itemID: itemID, entryID: entryModel.id)
        self.entryModel = entryModel
        self.versions = versions
        self.isExpanded = isExpanded
    }

    let id: SheetReviewEntryID
    let entryModel: SingleEntryImportModel
    let versions: [SheetReviewVersion]
    var isExpanded: Bool

    var decision: SingleReviewDecision {
        entryModel.decision
    }

    var hasDifferences: Bool {
        entryModel.hasDifferences
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    func select(_ decision: SingleReviewDecision) {
        entryModel.applyItemDecision(decision)
        isExpanded = false
    }
}

enum SheetReviewTreeBuilder {
    @MainActor
    private struct ReviewCandidate {
        let entryModel: SingleEntryImportModel
        let versions: [SheetReviewVersion]

        var id: UUID { entryModel.id }

        var visibleSheetModel: SheetModel? {
            versions.first(where: \.isAvailable)?.sheetModel
        }
    }

    @MainActor
    static func decorate(
        sheetModel: SheetModel,
        reviewItem: ImportReviewItemModel,
        versionSheets: [SingleReviewDecision: SheetModel]
    ) {
        guard reviewItem.kind == .different, !reviewItem.isDeletion else { return }

        let itemID = reviewItem.id
        let versionRows = versionSheets.mapValues { directRows(in: $0, itemID: itemID) }
        let candidates = reviewItem.itemModel.entries.compactMap { entryModel -> ReviewCandidate? in
            let versions = SingleReviewDecision.allCases.map { decision in
                SheetReviewVersion(
                    id: SheetReviewVersionID(itemID: itemID, entryID: entryModel.id, decision: decision),
                    decision: decision,
                    sheetModel: versionRows[decision]?[entryModel.id],
                    entry: entryModel.materializedEntry(for: decision)
                )
            }

            guard versions.contains(where: \.isAvailable) else { return nil }
            return ReviewCandidate(entryModel: entryModel, versions: versions)
        }
        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let candidateOrder = Dictionary(
            uniqueKeysWithValues: candidates.enumerated().map { ($0.element.id, $0.offset) }
        )
        var consumedEntryIDs: Set<UUID> = []
        var decoratedRows = sheetModel.entries

        // Decorate existing rows in place so the currently materialized sheet remains the
        // authority for ordering. This also preserves linked/foreign rows interleaved with
        // the reviewed item's direct entries.
        for row in decoratedRows {
            guard row.source.itemId == itemID,
                  let entryID = row.source.entryId,
                  let candidate = candidatesByID[entryID] else { continue }

            decorate(row, with: candidate, itemID: itemID)
            consumedEntryIDs.insert(entryID)
        }

        // Insert only rows omitted by the selected version. Their position follows the
        // stable union order without changing the relative order of any current rows.
        for candidate in candidates where !consumedEntryIDs.contains(candidate.id) {
            guard let visibleSheetModel = candidate.visibleSheetModel else { continue }
            let row = placeholder(from: visibleSheetModel)
            row.isReviewPlaceholder = true
            decorate(row, with: candidate, itemID: itemID)

            let order = candidateOrder[candidate.id] ?? candidates.count
            let insertionIndex = placeholderInsertionIndex(
                in: decoratedRows,
                itemID: itemID,
                candidateOrder: candidateOrder,
                order: order
            )
            decoratedRows.insert(row, at: insertionIndex)
            consumedEntryIDs.insert(candidate.id)
        }

        sheetModel.entries = decoratedRows
    }

    @MainActor
    private static func decorate(
        _ row: SheetModel,
        with candidate: ReviewCandidate,
        itemID: UUID
    ) {
        row.entryReviewModel = candidate.entryModel.hasDifferences
            ? SheetEntryReviewModel(
                itemID: itemID,
                entryModel: candidate.entryModel,
                versions: candidate.versions
            )
            : nil
    }

    @MainActor
    private static func placeholderInsertionIndex(
        in rows: [SheetModel],
        itemID: UUID,
        candidateOrder: [UUID: Int],
        order: Int
    ) -> Int {
        if let succeedingIndex = rows.firstIndex(where: { row in
            guard row.source.itemId == itemID,
                  let entryID = row.source.entryId,
                  let rowOrder = candidateOrder[entryID] else { return false }
            return rowOrder > order
        }) {
            return succeedingIndex
        }

        if let precedingIndex = rows.lastIndex(where: { row in
            guard row.source.itemId == itemID,
                  let entryID = row.source.entryId,
                  let rowOrder = candidateOrder[entryID] else { return false }
            return rowOrder < order
        }) {
            return precedingIndex + 1
        }

        return rows.endIndex
    }

    @MainActor
    private static func directRows(in sheetModel: SheetModel, itemID: UUID) -> [UUID: SheetModel] {
        sheetModel.entries.reduce(into: [:]) { result, row in
            guard row.source.itemId == itemID, let entryID = row.source.entryId else { return }
            result[entryID] = row
        }
    }

    @MainActor
    private static func placeholder(from sheetModel: SheetModel) -> SheetModel {
        SheetModel(
            source: sheetModel.source,
            destination: sheetModel.destination,
            level: sheetModel.level,
            type: sheetModel.sheetType,
            isShown: sheetModel.isShown,
            isFolded: sheetModel.isFolded,
            canAdd: false,
            editType: .none,
            showHeader: sheetModel.showHeader,
            name: sheetModel.name,
            description: "",
            entries: []
        )
    }
}

extension NetworkModules {
    var supportsStructuredImportReview: Bool {
        switch self {
        case .adventure, .map, .rule, .value, .table:
            true
        default:
            false
        }
    }
}
