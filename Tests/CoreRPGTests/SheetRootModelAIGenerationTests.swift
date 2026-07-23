// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
struct SheetRootModelAIGenerationTests {
    @Test("AI accessory requires meaningful non-root sheet content")
    func aiAssistantContentVisibility() throws {
        let fixture = try makeFixture()

        #expect(fixture.rootModel.hasAIAssistantContent)

        fixture.rootSheet.entries = [fixture.emptyEntry, fixture.generatedEntry]

        #expect(!fixture.rootModel.hasAIAssistantContent)
    }

    @Test("Root focus appends generation at the end of the root sheet")
    func rootFocusCreatesTrailingRequest() throws {
        // Given
        let fixture = try makeFixture()
        fixture.rootModel.setSelected(fixture.rootSheet, parent: fixture.rootSheet)

        // When
        let request = try #require(
            fixture.rootModel.queueGeneration(prompt: "Create a complication", module: .map)
        )

        // Then
        #expect(request.prompt == "Create a complication")
        #expect(request.focus.rootItemID == fixture.rootSheet.source.itemId)
        #expect(request.focus.parentModelID == fixture.rootSheet.id)
        #expect(request.focus.parentSource == fixture.rootSheet.source)
        #expect(request.focus.selectedModelID == nil)
        #expect(request.focus.selectedSource == nil)
        #expect(request.focus.position == .end)
        #expect(request.focus.module == .adventure)
        #expect(request.focusedContent == nil)
        #expect(fixture.rootModel.pendingGenerationRequest?.id == request.id)
        #expect(fixture.rootModel.isAIModeActive)
    }

    @Test("Top-level content focuses its parent sheet and inserts after the row")
    func topLevelContentCreatesAnchoredRequest() throws {
        // Given
        let fixture = try makeFixture()

        // When
        let request = try #require(
            fixture.rootModel.queueGeneration(
                from: fixture.topEntry,
                parent: fixture.rootSheet,
                module: .map
            )
        )

        // Then
        #expect(request.prompt.isEmpty)
        #expect(request.focus.parentModelID == fixture.rootSheet.id)
        #expect(request.focus.parentSource == fixture.rootSheet.source)
        #expect(request.focus.selectedModelID == fixture.topEntry.id)
        #expect(request.focus.selectedSource == fixture.topEntry.source)
        #expect(request.focus.position == .after(IDs.topEntry))
        #expect(request.focus.module == .adventure)
        #expect(request.focusedContent?.id == fixture.topEntry.id)
        #expect(request.focusedContent?.name == "Top Entry")
        #expect(request.focusedContent?.content == "Top-level content")
        #expect(request.focusedContent?.children.isEmpty == true)
    }

    @Test("Nested content targets the containing subsheet")
    func nestedContentCreatesSubsheetRequest() throws {
        // Given
        let fixture = try makeFixture()

        // When
        let request = try #require(
            fixture.rootModel.queueGeneration(
                from: fixture.nestedEntry,
                parent: fixture.nestedSheet,
                module: .adventure
            )
        )

        // Then
        #expect(request.focus.rootItemID == IDs.rootItem)
        #expect(request.focus.parentModelID == fixture.nestedSheet.id)
        #expect(request.focus.parentSource == fixture.nestedSheet.source)
        #expect(request.focus.selectedModelID == fixture.nestedEntry.id)
        #expect(request.focus.selectedSource == fixture.nestedEntry.source)
        #expect(request.focus.position == .after(IDs.nestedEntry))
        #expect(request.focus.module == .value)
        #expect(request.sheetContext.id == fixture.nestedSheet.id)
        #expect(request.sheetContext.children.map(\.id) == [fixture.nestedEntry.id])
        #expect(request.focusedContent?.id == fixture.nestedEntry.id)
    }

    @Test("Read-only linked content keeps its input while targeting the nearest editable sheet")
    func readOnlyLinkedContentFallsBackToContainingEditableSheet() throws {
        // Given
        let fixture = try makeFixture()
        let readOnlyEntry = SheetModel(
            source: ItemRowModel(itemId: IDs.readOnlyItem, entryId: IDs.readOnlyEntry, typeId: .none),
            level: 2,
            name: "Read-only Entry",
            description: "Use this original input",
            entries: []
        )
        let readOnlySheet = SheetModel(
            source: ItemRowModel(itemId: IDs.readOnlyItem, typeId: .none),
            level: 1,
            name: "Read-only Sheet",
            description: "Linked context",
            entries: [readOnlyEntry]
        )
        fixture.topEntry.entries.append(readOnlySheet)

        // When
        let request = try #require(
            fixture.rootModel.queueGeneration(
                from: readOnlyEntry,
                parent: readOnlySheet,
                module: .map
            )
        )

        // Then
        #expect(request.focus.parentModelID == fixture.rootSheet.id)
        #expect(request.focus.parentSource == fixture.rootSheet.source)
        #expect(request.focus.position == .after(IDs.topEntry))
        #expect(request.focus.module == .adventure)
        #expect(request.focus.selectedModelID == readOnlyEntry.id)
        #expect(request.focus.selectedSource == readOnlyEntry.source)
        #expect(request.focusedContent?.id == readOnlyEntry.id)
        #expect(request.focusedContent?.content == "Use this original input")
        #expect(request.sheetContext.id == fixture.rootSheet.id)
    }

    @Test("Sheet context excludes generated content and empty wrappers")
    func contextSnapshotContainsOnlySheetContent() throws {
        // Given
        let fixture = try makeFixture()
        fixture.rootModel.setSelected(fixture.rootSheet, parent: fixture.rootSheet)

        // When
        let request = try #require(
            fixture.rootModel.queueGeneration(prompt: "Use this sheet", module: .adventure)
        )
        let snapshotIDs = flattenedIDs(in: request.sheetContext)

        // Then
        #expect(request.sheetContext.name == "Root Sheet")
        #expect(request.sheetContext.content == "Root context")
        #expect(request.sheetContext.children.map(\.id) == [fixture.topEntry.id])
        #expect(snapshotIDs.contains(fixture.topEntry.id))
        #expect(snapshotIDs.contains(fixture.nestedSheet.id))
        #expect(snapshotIDs.contains(fixture.nestedEntry.id))
        #expect(!snapshotIDs.contains(fixture.emptyEntry.id))
        #expect(!snapshotIDs.contains(fixture.generatedEntry.id))
        #expect(!snapshotIDs.contains(fixture.emptyInlineWrapper.id))
    }

    @Test("A successful generation atomically replaces the previous preview batch")
    func successfulGenerationReplacesPreviousBatch() throws {
        // Given
        let fixture = try makeFixture()
        let firstRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "First request", module: .adventure)
        )
        let firstInstalled = fixture.rootModel.installGeneratedDrafts(
            [GeneratedSheetDraft(id: IDs.firstDraft, title: "First Title", content: "First Content")],
            for: firstRequest.id
        )
        let firstBatch = try #require(fixture.rootModel.generatedBatch)
        let firstPreview = try #require(firstBatch.entries.first)

        // When
        let secondRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "Second request", module: .adventure)
        )
        let secondInstalled = fixture.rootModel.installGeneratedDrafts(
            [GeneratedSheetDraft(id: IDs.secondDraft, title: "  Second Title  ", content: "\nSecond Content ")],
            for: secondRequest.id
        )
        let secondBatch = try #require(fixture.rootModel.generatedBatch)

        // Then
        #expect(firstInstalled)
        #expect(secondInstalled)
        #expect(firstBatch.id == firstRequest.id.uuidString)
        #expect(secondBatch.id == secondRequest.id.uuidString)
        #expect(secondBatch.id != firstBatch.id)
        #expect(secondBatch.entries.map { $0.source.entryId } == [IDs.secondDraft])
        #expect(secondBatch.entries.map(\.name) == ["Second Title"])
        #expect(secondBatch.entries.map(\.description) == ["Second Content"])
        #expect(secondBatch.entries.allSatisfy { $0.isGeneratedAnswer })
        #expect(secondBatch.entries.allSatisfy { $0.generatedBatchID == secondRequest.id.uuidString })
        #expect(!secondBatch.entries.contains { $0 === firstPreview })
        #expect(fixture.rootModel.pendingGenerationRequest == nil)
    }

    @Test("Finishing a failed request retains the previous preview batch")
    func failedRequestRetainsPreviousBatch() throws {
        // Given
        let fixture = try makeFixture()
        let successfulRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "Successful request", module: .adventure)
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.firstDraft, title: "Keep", content: "Keep this preview")],
                for: successfulRequest.id
            )
        )
        let retainedBatch = try #require(fixture.rootModel.generatedBatch)
        let retainedPreview = try #require(retainedBatch.entries.first)
        let failedRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "Failing request", module: .adventure)
        )

        // When
        fixture.rootModel.finishGenerationRequest(failedRequest.id)

        // Then
        #expect(fixture.rootModel.pendingGenerationRequest == nil)
        #expect(fixture.rootModel.generatedBatch?.id == retainedBatch.id)
        #expect(fixture.rootModel.generatedBatch?.entries.first === retainedPreview)
    }

    @Test("A finished request with no usable drafts retains the previous preview batch")
    func emptyResultRetainsPreviousBatch() throws {
        // Given
        let fixture = try makeFixture()
        let successfulRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "Successful request", module: .adventure)
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.firstDraft, title: "Keep", content: "Keep this preview")],
                for: successfulRequest.id
            )
        )
        let retainedBatch = try #require(fixture.rootModel.generatedBatch)
        let retainedPreview = try #require(retainedBatch.entries.first)
        let emptyRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "Empty request", module: .adventure)
        )

        // When
        let installed = fixture.rootModel.installGeneratedDrafts(
            [GeneratedSheetDraft(id: IDs.secondDraft, title: "  ", content: "\n")],
            for: emptyRequest.id
        )

        // Then
        #expect(!installed)
        #expect(fixture.rootModel.pendingGenerationRequest == nil)
        #expect(fixture.rootModel.generatedBatch?.id == retainedBatch.id)
        #expect(fixture.rootModel.generatedBatch?.entries.first === retainedPreview)
    }

    @Test("Resetting to another item clears all AI generation state")
    func itemResetClearsGenerationStateAndRejectsLateOutput() throws {
        // Given
        let fixture = try makeFixture()
        let completedRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "Completed request", module: .adventure)
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.firstDraft, title: "Preview", content: "Generated content")],
                for: completedRequest.id
            )
        )
        let pendingRequest = try #require(
            fixture.rootModel.queueGeneration(
                from: fixture.topEntry,
                parent: fixture.rootSheet,
                module: .adventure
            )
        )

        // When
        fixture.rootModel.reset(itemId: IDs.replacementItem)
        let installedLateOutput = fixture.rootModel.installGeneratedDrafts(
            [GeneratedSheetDraft(id: IDs.secondDraft, title: "Late", content: "Stale content")],
            for: pendingRequest.id
        )

        // Then
        #expect(fixture.rootModel.pendingGenerationRequest == nil)
        #expect(fixture.rootModel.generatedBatch == nil)
        #expect(!fixture.rootModel.isAIModeActive)
        #expect(fixture.rootModel.selectedEntryId == nil)
        #expect(!installedLateOutput)
    }

    @Test("Anchored previews are exposed only after their selected row")
    func anchoredPreviewPlacementUsesSelectedRow() throws {
        // Given
        let fixture = try makeFixture()
        let request = try #require(
            fixture.rootModel.queueGeneration(
                from: fixture.topEntry,
                parent: fixture.rootSheet,
                module: .adventure
            )
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [
                    GeneratedSheetDraft(id: IDs.firstDraft, title: "One", content: "First"),
                    GeneratedSheetDraft(id: IDs.secondDraft, title: "Two", content: "Second")
                ],
                for: request.id
            )
        )

        // When
        let anchored = fixture.rootModel.generatedEntries(after: fixture.topEntry, in: fixture.rootSheet)
        let afterDifferentRow = fixture.rootModel.generatedEntries(after: fixture.emptyEntry, in: fixture.rootSheet)
        let trailingWhileAnchorExists = fixture.rootModel.trailingGeneratedEntries(in: fixture.rootSheet)

        // Then
        #expect(anchored.map { $0.source.entryId } == [IDs.firstDraft, IDs.secondDraft])
        #expect(afterDifferentRow.isEmpty)
        #expect(trailingWhileAnchorExists.isEmpty)
        #expect(fixture.rootModel.editorModel.scrollEntryId == IDs.secondDraft)
        #expect(!fixture.rootSheet.entries.contains { $0.source.entryId == IDs.firstDraft })
        #expect(!fixture.rootSheet.entries.contains { $0.source.entryId == IDs.secondDraft })
    }

    @Test("Anchored previews fall back to the sheet end when their row disappears")
    func missingAnchorMovesPreviewsToTrailingPlacement() throws {
        // Given
        let fixture = try makeFixture()
        let request = try #require(
            fixture.rootModel.queueGeneration(
                from: fixture.topEntry,
                parent: fixture.rootSheet,
                module: .adventure
            )
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.firstDraft, title: "Fallback", content: "Trailing")],
                for: request.id
            )
        )

        // When
        fixture.rootSheet.entries.removeAll { $0 === fixture.topEntry }
        let trailing = fixture.rootModel.trailingGeneratedEntries(in: fixture.rootSheet)

        // Then
        #expect(trailing.map { $0.source.entryId } == [IDs.firstDraft])
    }

    @Test("Root requests expose generated previews at the sheet end")
    func rootPreviewPlacementIsTrailing() throws {
        // Given
        let fixture = try makeFixture()
        let request = try #require(
            fixture.rootModel.queueGeneration(prompt: "Append ideas", module: .adventure)
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.firstDraft, title: "Trailing", content: "At the end")],
                for: request.id
            )
        )

        // When
        let trailing = fixture.rootModel.trailingGeneratedEntries(in: fixture.rootSheet)
        let anchored = fixture.rootModel.generatedEntries(after: fixture.topEntry, in: fixture.rootSheet)

        // Then
        #expect(trailing.map { $0.source.entryId } == [IDs.firstDraft])
        #expect(anchored.isEmpty)
    }

    @Test("Refining a generated preview uses it as input and preserves its placement")
    func refiningGeneratedPreviewPreservesPlacement() throws {
        // Given
        let fixture = try makeFixture()
        let initialRequest = try #require(
            fixture.rootModel.queueGeneration(
                from: fixture.topEntry,
                parent: fixture.rootSheet,
                module: .adventure
            )
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [
                    GeneratedSheetDraft(id: IDs.firstDraft, title: "First Idea", content: "First draft"),
                    GeneratedSheetDraft(id: IDs.secondDraft, title: "Second Idea", content: "Second draft")
                ],
                for: initialRequest.id
            )
        )
        let initialBatch = try #require(fixture.rootModel.generatedBatch)
        let firstPreview = try #require(initialBatch.entries.first)
        let secondPreview = try #require(initialBatch.entries.last)

        // When
        let refinement = try #require(
            fixture.rootModel.refineGeneratedPreview(firstPreview, in: fixture.rootSheet)
        )

        // Then the current previews remain visible until refinement succeeds.
        #expect(fixture.rootModel.generatedBatch?.entries.first === firstPreview)
        #expect(fixture.rootModel.generatedBatch?.entries.last === secondPreview)
        #expect(refinement.prompt.localizedStandardContains("Refine"))
        #expect(refinement.focusedContent?.id == firstPreview.id)
        #expect(refinement.focusedContent?.source == firstPreview.source)
        #expect(refinement.focusedContent?.name == "First Idea")
        #expect(refinement.focusedContent?.content == "First draft")
        #expect(refinement.focus.parentModelID == fixture.rootSheet.id)
        #expect(refinement.focus.position == .after(IDs.topEntry))
        #expect(refinement.focus.module == .adventure)
        #expect(!flattenedIDs(in: refinement.sheetContext).contains(firstPreview.id))

        // And a successful refinement atomically replaces the unused batch in-place.
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.refinedDraft, title: "Refined Idea", content: "Improved draft")],
                for: refinement.id
            )
        )
        let refinedBatch = try #require(fixture.rootModel.generatedBatch)
        #expect(refinedBatch.entries.map { $0.source.entryId } == [IDs.refinedDraft])
        #expect(refinedBatch.entries.allSatisfy { $0.isGeneratedAnswer })
        #expect(fixture.rootModel.generatedEntries(after: fixture.topEntry, in: fixture.rootSheet).first === refinedBatch.entries.first)
        #expect(fixture.rootModel.editorModel.scrollEntryId == IDs.refinedDraft)
    }

    @Test("Deleting a generated preview is transient, individual, and cancels its refinement")
    func discardingGeneratedPreviewIsIndividualAndCancelsRefinement() throws {
        // Given
        let fixture = try makeFixture()
        let initialRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "Create options", module: .adventure)
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [
                    GeneratedSheetDraft(id: IDs.firstDraft, title: "Delete", content: "Remove me"),
                    GeneratedSheetDraft(id: IDs.secondDraft, title: "Keep", content: "Keep me")
                ],
                for: initialRequest.id
            )
        )
        let firstPreview = try #require(fixture.rootModel.generatedBatch?.entries.first)
        let secondPreview = try #require(fixture.rootModel.generatedBatch?.entries.last)
        let cachedBeforeDeletion = fixture.rootModel.linkTextModel(
            for: .entry(IDs.firstDraft),
            text: firstPreview.name
        )
        let refinement = try #require(
            fixture.rootModel.refineGeneratedPreview(firstPreview, in: fixture.rootSheet)
        )

        // When
        let discardedFirst = fixture.rootModel.discardGeneratedPreview(
            firstPreview,
            in: fixture.rootSheet
        )

        // Then
        #expect(discardedFirst)
        #expect(fixture.rootModel.pendingGenerationRequest == nil)
        #expect(fixture.rootModel.generatedBatch?.entries.count == 1)
        #expect(fixture.rootModel.generatedBatch?.entries.first === secondPreview)
        #expect(
            fixture.rootModel.linkTextModel(for: .entry(IDs.firstDraft), text: firstPreview.name)
                !== cachedBeforeDeletion
        )
        #expect(
            !fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.refinedDraft, title: "Late", content: "Must not return")],
                for: refinement.id
            )
        )
        #expect(!fixture.rootModel.discardGeneratedPreview(firstPreview, in: fixture.rootSheet))

        // And deleting the final preview clears the generated placement and stale scroll target.
        #expect(fixture.rootModel.discardGeneratedPreview(secondPreview, in: fixture.rootSheet))
        #expect(fixture.rootModel.generatedBatch == nil)
        #expect(fixture.rootModel.trailingGeneratedEntries(in: fixture.rootSheet).isEmpty)
        #expect(fixture.rootModel.editorModel.scrollEntryId == nil)
    }

    @Test("Remaining previews follow the last accepted row and fall back when it disappears")
    func remainingPreviewsUseEffectiveAcceptedPlacement() throws {
        // Given
        let fixture = try makeFixture()
        seedEditableItem(for: fixture.rootSheet.source.itemId, in: fixture.itemDataModel)
        defer { removeSeededItem(fixture.rootSheet.source.itemId, from: fixture.itemDataModel) }

        let request = try #require(
            fixture.rootModel.queueGeneration(
                from: fixture.topEntry,
                parent: fixture.rootSheet,
                module: .adventure
            )
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [
                    GeneratedSheetDraft(id: IDs.firstDraft, title: "One", content: "First"),
                    GeneratedSheetDraft(id: IDs.secondDraft, title: "Two", content: "Second")
                ],
                for: request.id
            )
        )
        let firstPreview = try #require(fixture.rootModel.generatedBatch?.entries.first)
        let cachedBeforeAcceptance = fixture.rootModel.linkTextModel(
            for: .entry(IDs.firstDraft),
            text: firstPreview.name
        )
        #expect(fixture.rootModel.editorModel.entryId == nil)

        // When
        let acceptedID = try #require(fixture.rootModel.acceptGeneratedPreview(firstPreview))
        let acceptedRow = SheetModel(
            source: ItemRowModel(itemId: IDs.rootItem, entryId: acceptedID, typeId: .adventure),
            level: 0,
            name: "Accepted",
            description: "Persisted",
            entries: []
        )
        fixture.rootSheet.entries.insert(acceptedRow, at: 1)

        // Then
        #expect(fixture.rootModel.editorModel.entryId == nil)
        #expect(
            fixture.rootModel.sheetRowGeometryMatch(
                for: acceptedRow,
                parent: fixture.rootSheet
            ).id == .generated(parent: fixture.rootSheet.id, draft: IDs.firstDraft)
        )
        #expect(
            fixture.rootModel.generatedEntries(after: acceptedRow, in: fixture.rootSheet)
                .map { $0.source.entryId } == [IDs.secondDraft]
        )
        #expect(fixture.rootModel.generatedEntries(after: fixture.topEntry, in: fixture.rootSheet).isEmpty)
        #expect(fixture.rootModel.trailingGeneratedEntries(in: fixture.rootSheet).isEmpty)
        let cachedAfterAcceptance = fixture.rootModel.linkTextModel(
            for: .entry(IDs.firstDraft),
            text: firstPreview.name
        )
        #expect(cachedAfterAcceptance !== cachedBeforeAcceptance)

        // And the temporary visual identity is discarded once the handoff completes.
        fixture.rootModel.finishGeneratedAcceptanceTransition(
            previewID: IDs.firstDraft,
            parentModelID: fixture.rootSheet.id
        )
        #expect(
            fixture.rootModel.sheetRowGeometryMatch(
                for: acceptedRow,
                parent: fixture.rootSheet
            ).id == .regular(parent: fixture.rootSheet.id, row: acceptedRow.id)
        )

        // And when the accepted row can no longer be resolved, placement uses the original anchor.
        fixture.rootSheet.entries.removeAll { $0 === acceptedRow }
        #expect(
            fixture.rootModel.generatedEntries(after: fixture.topEntry, in: fixture.rootSheet)
                .map { $0.source.entryId } == [IDs.secondDraft]
        )
    }

    @Test("A preview replaced by a newer generation cannot commit through the legacy path")
    func replacedExternalPreviewIsRejectedAsStale() throws {
        // Given
        let fixture = try makeFixture()
        let firstRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "First", module: .adventure)
        )
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.firstDraft, title: "Old", content: "Stale")],
                for: firstRequest.id
            )
        )
        let stalePreview = try #require(fixture.rootModel.generatedBatch?.entries.first)
        let staleCachedModel = fixture.rootModel.linkTextModel(
            for: .entry(IDs.firstDraft),
            text: stalePreview.name
        )
        let secondRequest = try #require(
            fixture.rootModel.queueGeneration(prompt: "Second", module: .adventure)
        )

        // When
        #expect(
            fixture.rootModel.installGeneratedDrafts(
                [GeneratedSheetDraft(id: IDs.secondDraft, title: "Current", content: "Keep")],
                for: secondRequest.id
            )
        )
        let committed = fixture.rootModel.commitGeneratedEntry(stalePreview, parent: fixture.rootSheet)
        let refinement = fixture.rootModel.refineGeneratedPreview(stalePreview, in: fixture.rootSheet)
        let discarded = fixture.rootModel.discardGeneratedPreview(stalePreview, in: fixture.rootSheet)

        // Then
        #expect(!committed)
        #expect(refinement == nil)
        #expect(!discarded)
        #expect(fixture.rootModel.generatedBatch?.entries.map { $0.source.entryId } == [IDs.secondDraft])
        #expect(stalePreview.isGeneratedAnswer)
        let refreshedCachedModel = fixture.rootModel.linkTextModel(
            for: .entry(IDs.firstDraft),
            text: stalePreview.name
        )
        #expect(refreshedCachedModel !== staleCachedModel)
    }
}

@MainActor
private extension SheetRootModelAIGenerationTests {
    struct Fixture {
        let rootModel: SheetRootModel
        let itemDataModel: ItemDataModel
        let rootSheet: SheetModel
        let topEntry: SheetModel
        let nestedSheet: SheetModel
        let nestedEntry: SheetModel
        let emptyEntry: SheetModel
        let generatedEntry: SheetModel
        let emptyInlineWrapper: SheetModel
    }

    enum IDs {
        static let rootItem = deterministicUUID(1)
        static let topEntry = deterministicUUID(2)
        static let emptyEntry = deterministicUUID(3)
        static let generatedEntry = deterministicUUID(4)
        static let nestedItem = deterministicUUID(5)
        static let nestedEntry = deterministicUUID(6)
        static let inlineItem = deterministicUUID(7)
        static let firstDraft = deterministicUUID(8)
        static let secondDraft = deterministicUUID(9)
        static let replacementItem = deterministicUUID(10)
        static let readOnlyItem = deterministicUUID(11)
        static let readOnlyEntry = deterministicUUID(12)
        static let refinedDraft = deterministicUUID(13)
    }

    func makeFixture() throws -> Fixture {
        let nestedEntry = SheetModel(
            source: ItemRowModel(itemId: IDs.nestedItem, entryId: IDs.nestedEntry, typeId: .value),
            level: 1,
            name: "Nested Entry",
            description: "Nested content",
            entries: []
        )
        let nestedSheet = SheetModel(
            source: ItemRowModel(itemId: IDs.nestedItem, typeId: .value),
            destination: ItemRowModel(itemId: IDs.rootItem, entryId: IDs.topEntry, typeId: .adventure),
            level: 1,
            isShown: true,
            name: "Nested Sheet",
            description: "Nested context",
            entries: [nestedEntry]
        )
        let topEntry = SheetModel(
            source: ItemRowModel(itemId: IDs.rootItem, entryId: IDs.topEntry, typeId: .adventure),
            level: 0,
            name: "Top Entry",
            description: "Top-level content",
            entries: [nestedSheet]
        )
        let emptyEntry = SheetModel(
            source: ItemRowModel(itemId: IDs.rootItem, entryId: IDs.emptyEntry, typeId: .adventure),
            level: 0,
            name: "  ",
            description: "\n",
            entries: []
        )
        let generatedEntry = SheetModel(
            source: ItemRowModel(itemId: IDs.rootItem, entryId: IDs.generatedEntry, typeId: .adventure),
            level: 0,
            name: "Old Generated Entry",
            description: "Must not become context",
            entries: []
        )
        generatedEntry.isGeneratedAnswer = true
        let emptyInlineWrapper = SheetModel(
            source: ItemRowModel(itemId: IDs.inlineItem, typeId: .photo),
            level: 0,
            type: .photo,
            name: "",
            description: "",
            entries: []
        )
        let rootSheet = SheetModel(
            source: ItemRowModel(itemId: IDs.rootItem, typeId: .adventure),
            level: 0,
            name: "Root Sheet",
            description: "Root context",
            inlineEntries: [emptyInlineWrapper],
            entries: [topEntry, emptyEntry, generatedEntry]
        )
        let itemRootController = ItemRootController.fake
        let rootManager = try #require(itemRootController.rootManager)
        let rootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: FakeLinkController.fake,
            sheetControllable: FakeSheetController.fake,
            sheetModel: rootSheet,
            isEditor: true
        )
        return Fixture(
            rootModel: rootModel,
            itemDataModel: itemRootController.itemControllable.itemDataModel,
            rootSheet: rootSheet,
            topEntry: topEntry,
            nestedSheet: nestedSheet,
            nestedEntry: nestedEntry,
            emptyEntry: emptyEntry,
            generatedEntry: generatedEntry,
            emptyInlineWrapper: emptyInlineWrapper
        )
    }

    func flattenedIDs(in snapshot: SheetContentSnapshot) -> [UUID] {
        [snapshot.id] + snapshot.children.flatMap(flattenedIDs)
    }

    func seedEditableItem(for itemID: UUID, in itemDataModel: ItemDataModel) {
        itemDataModel.itemData[itemID] = FakeItemModel(
            id: itemID,
            name: "Root",
            entries: []
        )
    }

    func removeSeededItem(_ itemID: UUID, from itemDataModel: ItemDataModel) {
        itemDataModel.itemData[itemID] = nil
    }

    nonisolated static func deterministicUUID(_ finalByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
    }
}
