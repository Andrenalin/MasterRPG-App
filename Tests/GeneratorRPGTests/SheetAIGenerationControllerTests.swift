// @copyright André Trettin

#if canImport(Testing) && !os(tvOS)
import CoreRPG
import Foundation
import Testing

@testable import GeneratorRPG

struct SheetAIGenerationControllerTests {
    @Test("Prompt identifies the target module and focused sheet content")
    func promptIncludesModuleFocusAndContainingContext() {
        // Given
        let request = makeRequest(
            prompt: "Add a concealed route",
            module: .map,
            focusedContent: focusedSnapshot
        )

        // When
        let prompt = SheetAIGenerationController.prompt(for: request)

        // Then
        #expect(prompt.contains("module type MAPS"))
        #expect(prompt.contains("Game master's request:\nAdd a concealed route"))
        #expect(prompt.contains("Focused content:"))
        #expect(prompt.contains("Title: Gatehouse"))
        #expect(prompt.contains("Content: The portcullis is locked."))
        #expect(prompt.contains("Containing sheet context:"))
        #expect(prompt.contains("Title: Ancient Keep"))
        #expect(prompt.contains("Content: A ruined fortress above the valley."))
    }

    @Test("Prompt length is bounded while retaining focused and containing context")
    func longUserPromptRetainsRequiredSheetContext() {
        // Given
        let request = makeRequest(
            prompt: String(repeating: "Long request detail. ", count: 1_000),
            module: .map,
            focusedContent: focusedSnapshot
        )
        let maximumCharacterCount = 1_600

        // When
        let prompt = SheetAIGenerationController.prompt(
            for: request,
            maxCharacters: maximumCharacterCount
        )

        // Then
        #expect(prompt.count <= maximumCharacterCount)
        #expect(prompt.contains("module type MAPS"))
        #expect(prompt.contains("Game master's request:"))
        #expect(prompt.contains(FoundationModelInputLimiter.truncationMarker))
        #expect(prompt.contains("Focused content:"))
        #expect(prompt.contains("Title: Gatehouse"))
        #expect(prompt.contains("Content: The portcullis is locked."))
        #expect(prompt.contains("Containing sheet context:"))
        #expect(prompt.contains("Title: Ancient Keep"))
        #expect(prompt.contains("Content: A ruined fortress above the valley."))
    }

    @Test("Deep sheet traversal stops when the context budget is exhausted")
    func deepSheetContextUsesIncrementalBoundedTraversal() {
        // Given
        let depth = 1_000
        let deepContext = makeDeepSnapshot(depth: depth)
        let request = makeRequest(
            prompt: "Continue this location",
            module: .map,
            focusedContent: focusedSnapshot,
            sheetContext: deepContext
        )
        let maximumCharacterCount = 1_400

        // When
        let prompt = SheetAIGenerationController.prompt(
            for: request,
            maxCharacters: maximumCharacterCount
        )

        // Then
        #expect(prompt.count <= maximumCharacterCount)
        #expect(prompt.contains("Focused content:"))
        #expect(prompt.contains("Title: Gatehouse"))
        #expect(prompt.contains("Containing sheet context:"))
        #expect(prompt.contains("Title: Depth 0"))
        #expect(prompt.contains(FoundationModelInputLimiter.truncationMarker))
        #expect(!prompt.contains("Deep leaf sentinel"))
    }

    @Test("Block entries map to trimmed drafts while empty entries are filtered")
    func draftsMapUsableEntriesAndFilterEmptyEntries() {
        // Given
        let block = BlockGenModel(
            name: "Top-level fallback",
            information: "This must not replace usable entries.",
            blockCategory: .adventure,
            entries: [
                BlockEntryGenModel(title: "  Opening Scene  ", content: "  Bells ring at dusk.  "),
                BlockEntryGenModel(title: "\n", content: "  "),
                BlockEntryGenModel(title: "", content: "A content-only consequence.\n")
            ]
        )

        // When
        let drafts = SheetAIGenerationController.drafts(from: block)

        // Then
        #expect(drafts.map(\.title) == ["Opening Scene", ""])
        #expect(drafts.map(\.content) == ["Bells ring at dusk.", "A content-only consequence."])
    }

    @Test("Block metadata becomes one draft when no usable entries exist")
    func draftsFallBackToTopLevelBlockContent() {
        // Given
        let block = BlockGenModel(
            name: "  Storm Front  ",
            information: "  Lightning closes the mountain pass.\n",
            blockCategory: .map,
            entries: [
                BlockEntryGenModel(title: " ", content: "\n")
            ]
        )

        // When
        let drafts = SheetAIGenerationController.drafts(from: block)

        // Then
        #expect(drafts.count == 1)
        #expect(drafts.first?.title == "Storm Front")
        #expect(drafts.first?.content == "Lightning closes the mountain pass.")
    }

    @Test("Completely empty block output produces no drafts")
    func draftsRejectCompletelyEmptyBlock() {
        // Given
        let block = BlockGenModel(
            name: " ",
            information: "\n",
            blockCategory: .table,
            entries: []
        )

        // When
        let drafts = SheetAIGenerationController.drafts(from: block)

        // Then
        #expect(drafts.isEmpty)
    }
}

private extension SheetAIGenerationControllerTests {
    var focusedSnapshot: SheetContentSnapshot {
        SheetContentSnapshot(
            id: IDs.focusedSnapshot,
            source: ItemRowModel(
                itemId: IDs.rootItem,
                entryId: IDs.focusedEntry,
                typeId: .map
            ),
            name: "Gatehouse",
            content: "The portcullis is locked."
        )
    }

    var rootSnapshot: SheetContentSnapshot {
        SheetContentSnapshot(
            id: IDs.rootSnapshot,
            source: ItemRowModel(itemId: IDs.rootItem, typeId: .map),
            name: "Ancient Keep",
            content: "A ruined fortress above the valley.",
            children: [focusedSnapshot]
        )
    }

    func makeRequest(
        prompt: String,
        module: NetworkModules,
        focusedContent: SheetContentSnapshot?,
        sheetContext: SheetContentSnapshot? = nil
    ) -> SheetGenerationRequest {
        let activeSheetContext = sheetContext ?? rootSnapshot
        let parentSource = ItemRowModel(itemId: IDs.rootItem, typeId: module)
        let selectedSource = focusedContent?.source
        return SheetGenerationRequest(
            id: IDs.request,
            prompt: prompt,
            sheetContext: activeSheetContext,
            focusedContent: focusedContent,
            focus: SheetGenerationFocus(
                rootItemID: IDs.rootItem,
                parentModelID: activeSheetContext.id,
                parentSource: parentSource,
                selectedModelID: focusedContent?.id,
                selectedSource: selectedSource,
                position: selectedSource?.entryId.map(SheetInsertionPosition.after) ?? .end,
                module: module
            )
        )
    }

    func makeDeepSnapshot(depth: Int) -> SheetContentSnapshot {
        var snapshot = SheetContentSnapshot(
            id: UUID(),
            source: ItemRowModel(
                itemId: IDs.rootItem,
                entryId: IDs.focusedEntry,
                typeId: .map
            ),
            name: "Deep leaf sentinel",
            content: "This content must be beyond the prompt budget."
        )

        for index in (0..<depth).reversed() {
            snapshot = SheetContentSnapshot(
                id: UUID(),
                source: ItemRowModel(
                    itemId: IDs.rootItem,
                    entryId: IDs.focusedEntry,
                    typeId: .map
                ),
                name: "Depth \(index)",
                content: "Context at depth \(index).",
                children: [snapshot]
            )
        }
        return snapshot
    }

    enum IDs {
        static let rootItem = deterministicUUID(1)
        static let focusedEntry = deterministicUUID(2)
        static let request = deterministicUUID(3)
        static let focusedSnapshot = deterministicUUID(4)
        static let rootSnapshot = deterministicUUID(5)
    }

    static func deterministicUUID(_ finalByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
    }
}
#endif
