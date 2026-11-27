// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
@Suite("Import Review Sheet Models")
struct ReviewSheetMemoryTests {
    @Test(
        "Structured review is enabled only for sheet-first modules",
        arguments: [NetworkModules.adventure, .map, .rule, .value, .table]
    )
    func structuredModulesUseInlineReview(_ module: NetworkModules) {
        // Given / When / Then
        #expect(module.supportsStructuredImportReview)
    }

    @Test(
        "Other modules keep the legacy Choices presentation",
        arguments: [
            NetworkModules.audio,
            .dice,
            .generator,
            .pdf,
            .photo,
            .space,
            .weather
        ]
    )
    func nonStructuredModulesKeepLegacyReview(_ module: NetworkModules) {
        // Given / When / Then
        #expect(!module.supportsStructuredImportReview)
    }

    @Test func reviewAwareLookupPrefersReviewMemory() {
        // Given
        let itemId = UUID.fixture1
        let liveItem = FakeItemModel(id: itemId, name: "Live Item")
        let reviewItem = FakeItemModel(id: itemId, name: "Review Item")
        let controller = fakeController(with: liveItem)
        let rootManager = RootManager(
            anyRoot: ItemRootController.fake,
            reviewSheetMemory: ReviewSheetMemory(items: [.adventure: [itemId: reviewItem]])
        )

        // When
        let result = controller.reviewAwareItemOrEmpty(root: rootManager, for: itemId)

        // Then
        #expect(result.name == "Review Item")
    }

    @Test func reviewAwareLookupCanHideLiveItem() {
        // Given
        let itemId = UUID.fixture1
        let liveItem = FakeItemModel(id: itemId, name: "Live Item")
        let controller = fakeController(with: liveItem)
        let rootManager = RootManager(
            anyRoot: ItemRootController.fake,
            reviewSheetMemory: ReviewSheetMemory(
                items: [:],
                hiddenItemIds: [.adventure: [itemId]]
            )
        )

        // When
        let hidden = controller.reviewAwareItemSync(root: rootManager, for: itemId)
        let empty = controller.reviewAwareItemOrEmpty(root: rootManager, for: itemId)

        // Then
        #expect(hidden == nil)
        #expect(empty.id == itemId)
        #expect(empty.name.isEmpty)
    }

    @Test func itemDecisionCascadesAndChangesSignature() throws {
        // Given
        let sut = makeReviewItem().itemModel
        let originalSignature = sut.decisionSignature

        // When
        sut.applyItemDecision(.existing)

        // Then
        #expect(sut.decision == .existing)
        #expect(sut.properties.allSatisfy { $0.decision == .existing })
        #expect(sut.entries.allSatisfy { $0.decision == .existing })
        #expect(sut.entries.flatMap(\.properties).allSatisfy { $0.decision == .existing })
        #expect(sut.decisionSignature != originalSignature)

        let changedSignature = sut.decisionSignature
        sut.entries[0].applyItemDecision(.imported)
        #expect(sut.decisionSignature != changedSignature)
        #expect(sut.hasOverrides)
    }

    @Test func wholeVersionMaterializationDoesNotMutateCurrentChoices() throws {
        // Given
        let sut = makeReviewItem().itemModel
        sut.applyItemDecision(.existing)
        let entry = try #require(sut.entries.first)
        entry.applyItemDecision(.merge)
        let signature = sut.decisionSignature

        // When
        let imported = try #require(sut.materializedItem(for: .imported) as? FakeItemModel)
        let importedEntry = try #require(imported.entries.first)
        let mergedEntry = try #require(entry.materializedEntry(for: .merge) as? FakeEntryModel)

        // Then
        #expect(imported.name == "Imported Item")
        #expect(imported.description == "Imported Description")
        #expect(importedEntry.name == "Imported Entry")
        #expect(importedEntry.content == "Imported Content")
        #expect(mergedEntry.name == "Merged Entry")
        #expect(mergedEntry.content == "Merged Content")
        #expect(sut.decision == .existing)
        #expect(entry.decision == .merge)
        #expect(sut.decisionSignature == signature)
    }

    @Test func currentMaterializationKeepsEntryOverride() throws {
        // Given
        let sut = makeReviewItem().itemModel
        sut.applyItemDecision(.existing)
        let entry = try #require(sut.entries.first)
        entry.applyItemDecision(.imported)

        // When
        let materialized = try #require(sut.materializedItem() as? FakeItemModel)
        let materializedEntry = try #require(materialized.entries.first)

        // Then
        #expect(materialized.name == "Existing Item")
        #expect(materializedEntry.name == "Imported Entry")
        #expect(materializedEntry.content == "Imported Content")
    }

    @Test func semanticDifferenceUsesConcreteEntryComparison() {
        // Given
        let existing = SemanticReviewEntry(
            id: .fixture2,
            name: "Same Name",
            content: "Same Content",
            semanticValue: 1
        )
        let imported = SemanticReviewEntry(
            id: .fixture2,
            name: "Same Name",
            content: "Same Content",
            semanticValue: 2
        )
        let unchanged = SemanticReviewEntry(
            id: .fixture2,
            name: "Same Name",
            content: "Same Content",
            semanticValue: 1
        )

        // When
        let changedModel = SingleReviewEntry(existing: existing, imported: imported, merged: imported)
        let unchangedModel = SingleReviewEntry(existing: existing, imported: unchanged, merged: unchanged)
        let removedModel = SingleReviewEntry(existing: existing, imported: nil, merged: nil)

        // Then
        #expect(changedModel.hasDifferences)
        #expect(!unchangedModel.hasDifferences)
        #expect(removedModel.hasDifferences)
    }

    @Test func versionIdentitiesAreUniqueAndStable() throws {
        // Given
        let itemId = UUID.fixture1
        let entryId = UUID.fixture2

        // When
        let identities = SingleReviewDecision.allCases.map {
            SheetReviewVersionID(itemId: itemId, entryID: entryId, decision: $0)
        }
        let repeated = SheetReviewVersionID(itemId: itemId, entryID: entryId, decision: .merge)

        // Then
        #expect(Set(identities).count == SingleReviewDecision.allCases.count)
        #expect(identities[0] == repeated)
    }

    @Test func decorationBuildsUnionAndPlaceholdersForMissingVersions() throws {
        // Given
        let itemId = UUID.fixture1
        let existingOnly = FakeEntryModel(id: .fixture2, name: "Existing only", content: "Old")
        let sharedExisting = FakeEntryModel(id: .fixture3, name: "Shared", content: "Old")
        let sharedImported = FakeEntryModel(id: .fixture3, name: "Shared", content: "New")
        let importedOnly = FakeEntryModel(id: .fixture4, name: "Imported only", content: "New")
        let existing = FakeItemModel(
            id: itemId,
            name: "Existing",
            entries: [existingOnly, sharedExisting]
        )
        let imported = FakeItemModel(
            id: itemId,
            name: "Imported",
            entries: [sharedImported, importedOnly]
        )
        let merged = FakeItemModel(
            id: itemId,
            name: "Merged",
            entries: [sharedImported, importedOnly]
        )
        let itemModel = SingleItemImportModel.from(
            item: SingleReviewItem(existing: existing, imported: imported, merged: merged)
        )
        itemModel.applyItemDecision(.imported)
        let reviewItem = ImportReviewItemModel(
            id: itemId,
            kind: .different,
            itemModel: itemModel
        )
        let currentSheet = sheet(itemId: itemId, entryIDs: [.fixture3, .fixture4])
        let versionSheets: [SingleReviewDecision: SheetModel] = [
            .existing: sheet(itemId: itemId, entryIDs: [.fixture2, .fixture3]),
            .imported: sheet(itemId: itemId, entryIDs: [.fixture3, .fixture4]),
            .merge: sheet(itemId: itemId, entryIDs: [.fixture3, .fixture4])
        ]

        // When
        SheetReviewTreeBuilder.decorate(
            sheetModel: currentSheet,
            reviewItem: reviewItem,
            versionSheets: versionSheets
        )

        // Then
        #expect(currentSheet.entries.compactMap(\.source.entryId) == [.fixture2, .fixture3, .fixture4])
        let existingPlaceholder = try #require(currentSheet.entries.first)
        #expect(existingPlaceholder.isReviewPlaceholder)
        #expect(existingPlaceholder.entryReviewModel?.versions.count == 3)
        #expect(existingPlaceholder.entryReviewModel?.versions.first { $0.decision == .imported }?.isAvailable == false)

        let importedRow = try #require(currentSheet.entries.first { $0.source.entryId == .fixture4 })
        #expect(!importedRow.isReviewPlaceholder)
        #expect(importedRow.entryReviewModel?.versions.first { $0.decision == .existing }?.isAvailable == false)
    }

    @Test func decorationPreservesCurrentAndForeignRowOrder() throws {
        // Given
        let itemId = UUID.fixture1
        let foreignItemID = UUID.fixture5
        let entryA = UUID.fixture2
        let entryB = UUID.fixture3
        let existingOnly = UUID.fixture4
        let existing = FakeItemModel(
            id: itemId,
            name: "Existing",
            entries: [
                FakeEntryModel(id: entryB, name: "B", content: "Existing B"),
                FakeEntryModel(id: existingOnly, name: "Removed", content: "Existing only"),
                FakeEntryModel(id: entryA, name: "A", content: "Existing A")
            ]
        )
        let imported = FakeItemModel(
            id: itemId,
            name: "Imported",
            entries: [
                FakeEntryModel(id: entryA, name: "A", content: "Imported A"),
                FakeEntryModel(id: entryB, name: "B", content: "Imported B")
            ]
        )
        let merged = FakeItemModel(
            id: itemId,
            name: "Merged",
            entries: [
                FakeEntryModel(id: entryA, name: "A", content: "Merged A"),
                FakeEntryModel(id: entryB, name: "B", content: "Merged B")
            ]
        )
        let itemModel = SingleItemImportModel.from(
            item: SingleReviewItem(existing: existing, imported: imported, merged: merged)
        )
        itemModel.applyItemDecision(.imported)
        let reviewItem = ImportReviewItemModel(
            id: itemId,
            kind: .different,
            itemModel: itemModel
        )
        let foreignA = sheetRow(itemId: foreignItemID, entryId: entryA, name: "Foreign A")
        let currentA = sheetRow(itemId: itemId, entryId: entryA, name: "Current A")
        let foreignRemoved = sheetRow(itemId: foreignItemID, entryId: existingOnly, name: "Foreign Removed")
        let currentB = sheetRow(itemId: itemId, entryId: entryB, name: "Current B")
        let currentSheet = SheetModel(
            source: ItemRowModel(itemId: itemId, typeId: .adventure),
            name: "Review Sheet",
            description: "",
            entries: [foreignA, currentA, foreignRemoved, currentB]
        )
        let versionSheets: [SingleReviewDecision: SheetModel] = [
            .existing: sheet(itemId: itemId, entryIDs: [entryB, existingOnly, entryA]),
            .imported: sheet(itemId: itemId, entryIDs: [entryA, entryB]),
            .merge: sheet(itemId: itemId, entryIDs: [entryA, entryB])
        ]

        // When
        SheetReviewTreeBuilder.decorate(
            sheetModel: currentSheet,
            reviewItem: reviewItem,
            versionSheets: versionSheets
        )

        // Then
        let rowsWithoutPlaceholder = currentSheet.entries.filter { !$0.isReviewPlaceholder }
        #expect(rowsWithoutPlaceholder.count == 4)
        #expect(rowsWithoutPlaceholder[0] === foreignA)
        #expect(rowsWithoutPlaceholder[1] === currentA)
        #expect(rowsWithoutPlaceholder[2] === foreignRemoved)
        #expect(rowsWithoutPlaceholder[3] === currentB)
        #expect(foreignA.entryReviewModel == nil)
        #expect(foreignRemoved.entryReviewModel == nil)

        let placeholder = try #require(
            currentSheet.entries.first { $0.isReviewPlaceholder }
        )
        #expect(placeholder.source.itemId == itemId)
        #expect(placeholder.source.entryId == existingOnly)
        #expect(placeholder.entryReviewModel != nil)
    }

    @Test func selectingAnotherVersionRestoresAnOmittedRowOnRebuild() throws {
        // Given
        let reviewItem = makeExistingOnlyReviewItem()
        reviewItem.itemModel.applyItemDecision(.imported)
        let importedSheet = sheet(itemId: reviewItem.id, entryIDs: [])
        let versions: [SingleReviewDecision: SheetModel] = [
            .existing: sheet(itemId: reviewItem.id, entryIDs: [.fixture2]),
            .imported: sheet(itemId: reviewItem.id, entryIDs: []),
            .merge: sheet(itemId: reviewItem.id, entryIDs: [])
        ]
        SheetReviewTreeBuilder.decorate(
            sheetModel: importedSheet,
            reviewItem: reviewItem,
            versionSheets: versions
        )
        let placeholder = try #require(importedSheet.entries.first)
        let review = try #require(placeholder.entryReviewModel)

        // When
        review.select(.existing)
        let existingSheet = sheet(itemId: reviewItem.id, entryIDs: [.fixture2])
        SheetReviewTreeBuilder.decorate(
            sheetModel: existingSheet,
            reviewItem: reviewItem,
            versionSheets: versions
        )

        // Then
        #expect(reviewItem.itemModel.entries[0].decision == .existing)
        #expect(!review.isExpanded)
        #expect(existingSheet.entries.first?.source.entryId == .fixture2)
        #expect(existingSheet.entries.first?.isReviewPlaceholder == false)
    }

    @Test func unchangedEntriesHaveNoInlineReviewControl() throws {
        // Given
        let entry = FakeEntryModel(id: .fixture2, name: "Same", content: "Same")
        let item = FakeItemModel(id: .fixture1, name: "Item", entries: [entry])
        let itemModel = SingleItemImportModel.from(
            item: SingleReviewItem(existing: item, imported: item, merged: item)
        )
        let reviewItem = ImportReviewItemModel(
            id: item.id,
            kind: .different,
            itemModel: itemModel
        )
        let currentSheet = sheet(itemId: item.id, entryIDs: [entry.id])
        let versions = Dictionary(
            uniqueKeysWithValues: SingleReviewDecision.allCases.map {
                ($0, sheet(itemId: item.id, entryIDs: [entry.id]))
            }
        )

        // When
        SheetReviewTreeBuilder.decorate(
            sheetModel: currentSheet,
            reviewItem: reviewItem,
            versionSheets: versions
        )

        // Then
        let row = try #require(currentSheet.entries.first)
        #expect(row.entryReviewModel == nil)
        #expect(!row.isReviewPlaceholder)
    }

    @Test func reviewMemoryUsesCurrentDecisionAndCanOverrideWithoutMutation() throws {
        // Given
        let reviewItem = makeReviewItem()
        let reviewModel = ImportReviewModel(modules: [
            ImportReviewModule(id: .adventure, reviewItems: [reviewItem])
        ])
        reviewItem.itemModel.applyItemDecision(.existing)
        let signature = reviewItem.itemModel.decisionSignature

        // When
        let current = try #require(
            reviewModel.sheetMemory().item(for: reviewItem.id, module: .adventure) as? FakeItemModel
        )
        let imported = try #require(
            reviewModel.sheetMemory(
                overriding: reviewItem.id,
                module: .adventure,
                decision: .imported
            ).item(for: reviewItem.id, module: .adventure) as? FakeItemModel
        )

        // Then
        #expect(current.name == "Existing Item")
        #expect(imported.name == "Imported Item")
        #expect(reviewItem.itemModel.decision == .existing)
        #expect(reviewItem.itemModel.decisionSignature == signature)
    }

    @Test func reviewMemoryHidesDeletionAndRejectedAddition() {
        // Given
        let deletion = makeReviewItem(isDeletion: true)
        deletion.itemModel.applyItemDecision(.imported)
        let addition = makeReviewItem(kind: .added)
        addition.itemModel.applyItemDecision(.existing)
        let reviewModel = ImportReviewModel(modules: [
            ImportReviewModule(id: .adventure, reviewItems: [deletion, addition])
        ])

        // When
        let memory = reviewModel.sheetMemory()

        // Then
        #expect(memory.hides(itemId: deletion.id, module: .adventure))
        #expect(memory.hides(itemId: addition.id, module: .adventure))
        #expect(memory.item(for: deletion.id, module: .adventure) == nil)
        #expect(memory.item(for: addition.id, module: .adventure) == nil)
    }

    private func makeReviewItem(
        kind: ImportReviewItemModel.ChangeKind = .different,
        isDeletion: Bool = false
    ) -> ImportReviewItemModel {
        let itemId = kind == .added ? UUID.fixture5 : UUID.fixture1
        let entryId = UUID.fixture2
        let existing = FakeItemModel(
            id: itemId,
            name: "Existing Item",
            description: "Existing Description",
            entries: [FakeEntryModel(id: entryId, name: "Existing Entry", content: "Existing Content")]
        )
        let imported = FakeItemModel(
            id: itemId,
            name: "Imported Item",
            description: "Imported Description",
            entries: [FakeEntryModel(id: entryId, name: "Imported Entry", content: "Imported Content")]
        )
        let merged = FakeItemModel(
            id: itemId,
            name: "Merged Item",
            description: "Merged Description",
            entries: [FakeEntryModel(id: entryId, name: "Merged Entry", content: "Merged Content")]
        )
        let itemModel = SingleItemImportModel.from(
            item: SingleReviewItem(
                existing: kind == .added ? nil : existing,
                imported: imported,
                merged: merged
            )
        )
        return ImportReviewItemModel(
            id: itemId,
            kind: kind,
            itemModel: itemModel,
            isDeletion: isDeletion
        )
    }

    private func makeExistingOnlyReviewItem() -> ImportReviewItemModel {
        let existingEntry = FakeEntryModel(id: .fixture2, name: "Removed", content: "Old")
        let existing = FakeItemModel(id: .fixture1, name: "Existing", entries: [existingEntry])
        let imported = FakeItemModel(id: .fixture1, name: "Imported", entries: [])
        let merged = FakeItemModel(id: .fixture1, name: "Merged", entries: [])
        let itemModel = SingleItemImportModel.from(
            item: SingleReviewItem(existing: existing, imported: imported, merged: merged)
        )
        return ImportReviewItemModel(
            id: .fixture1,
            kind: .different,
            itemModel: itemModel
        )
    }

    private func sheet(itemId: UUID, entryIDs: [UUID]) -> SheetModel {
        SheetModel(
            source: ItemRowModel(itemId: itemId, typeId: .adventure),
            name: "Review Sheet",
            description: "",
            entries: entryIDs.map { entryId in
                SheetModel(
                    source: ItemRowModel(itemId: itemId, entryId: entryId, typeId: .adventure),
                    name: "Entry \(entryId.uuidString)",
                    description: "Content \(entryId.uuidString)",
                    entries: []
                )
            }
        )
    }

    private func sheetRow(itemId: UUID, entryId: UUID, name: String) -> SheetModel {
        SheetModel(
            source: ItemRowModel(itemId: itemId, entryId: entryId, typeId: .adventure),
            name: name,
            description: "Content",
            entries: []
        )
    }

    private func fakeController(with item: FakeItemModel) -> FakeItemController {
        let itemDataModel = ItemDataModel()
        itemDataModel.items = [item.id]
        itemDataModel.itemData[item.id] = item

        return FakeItemController(
            config: FakeModuleConfiguration(),
            linkRegisterController: LinkRegisterController.fake,
            itemDataModel: itemDataModel
        )
    }
}

private struct SemanticReviewEntry: EntryDataAccessible {
    static var empty: SemanticReviewEntry {
        SemanticReviewEntry(id: .fixture1, name: "", content: "", semanticValue: 0)
    }

    static func newChild(id: UUID) -> SemanticReviewEntry {
        SemanticReviewEntry(id: id, name: "", content: "", semanticValue: 0)
    }

    let id: UUID
    var childId: UUID { id }
    var name: String
    var content: String
    let semanticValue: Int
    var displayState: Int = 0

    func duplicate() -> SemanticReviewEntry {
        self
    }
}

extension SemanticReviewEntry: ItemDiffComparable {
    @MainActor
    func isSame(_ other: SemanticReviewEntry) -> Bool {
        name == other.name && content == other.content && semanticValue == other.semanticValue
    }

    @MainActor
    func merge(_ other: SemanticReviewEntry) -> SemanticReviewEntry {
        other
    }
}
