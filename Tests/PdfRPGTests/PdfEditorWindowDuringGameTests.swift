// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
@testable import CoreRPG
import Foundation
import GeneratorRPG
import Testing

@testable import PdfRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded PDF shows it too, while a
/// change only the game copy has (here its description) stays out of the library.
@Suite("PDF editor window during a game")
@MainActor
struct PdfEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: PdfRootModel
        let itemId: UUID
        let entryId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (PdfModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: PdfEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: PdfEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }
    }

    /// A PDF with one bookmark in the library and the database, a running game and, when
    /// `loaded`, the PDF in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, PdfRPG.Resources.bundle])
        let root = PdfRootModel.testRoot()
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.pdf.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Rulebook", description: Self.libraryDescription, category: nil, tags: ["core"])
        let entry = PdfEntryModel(id: UUID(), name: "Combat", content: "Initiative", pageNumber: "12", bounds: .zero)
        root.editController.addBookmark(itemId: itemId, entry: entry)

        let fixture = Fixture(store: store, root: root, itemId: itemId, entryId: entry.id)
        fixture.game.startGame()
        if loaded {
            fixture.game.loadIntoGame(itemId) { $0.description = Self.sessionDescription }
        }
        // Selecting the item in the editor starts its undo history.
        root.editController.editorModel.undoManaged.resetValue(root.editController.editModel(for: itemId))
        return fixture
    }

    @Test("The header editor's name, tags and category reach the database and the game copy")
    func headerEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(id: fixture.itemId, name: "Player's Rulebook", description: nil, category: .adventure, tags: ["core", "rules"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Player's Rulebook" && $0.tags == ["core", "rules"] && $0.category == .adventure }
    }

    @Test("The entry editor's bookmark name and text reach the database and the game copy")
    func entryEditorEdit() async throws {
        let fixture = try await makeFixture()

        fixture.root.editController.update(itemId: fixture.itemId, entryId: fixture.entryId, name: "Melee", content: "Attack roll", forceSave: true)

        try await fixture.expectEdit { pdf in
            pdf.entries.first { $0.id == fixture.entryId }.map { $0.name == "Melee" && $0.content == "Attack roll" } ?? false
        }
    }

    @Test("A bookmark added from the selection bar reaches the database and the game copy")
    func addBookmark() async throws {
        let fixture = try await makeFixture()
        let bookmark = PdfEntryModel(id: UUID(), name: "Magic", content: "Spells", pageNumber: "40", bounds: .zero)

        fixture.root.editController.addBookmark(itemId: fixture.itemId, entry: bookmark, forceSave: true)

        try await fixture.expectEdit { $0.entries.map(\.id) == [fixture.entryId, bookmark.id] }
    }

    @Test("A bookmark removed in the editor is removed in the database and the game copy")
    func removeBookmark() async throws {
        let fixture = try await makeFixture()

        let removed = fixture.root.editController.removeEntry(source: ItemRowModel(itemId: fixture.itemId, entryId: fixture.entryId, typeId: .pdf), forceSave: true)

        #expect(removed)
        try await fixture.expectEdit { $0.entries.isEmpty }
    }

    @Test("Extracted title, tags and sections applied in the editor reach the database and the game copy")
    func applyExtractedContent() async throws {
        let fixture = try await makeFixture()
        let analysis = PdfSummaryAnalysis(
            title: "Dragon Rules",
            summary: "Not applied",
            tags: ["dragon", "rules"],
            sections: [PdfSection(heading: "Lairs", summary: "Where dragons live", pageNumber: 3)]
        )

        fixture.root.editController.applyExtractedContent(analysis, to: fixture.itemId, selection: PdfPropertySelection(applyDescription: false), forceSave: true)

        try await fixture.expectEdit { pdf in
            pdf.name == "Dragon Rules" && pdf.tags == ["dragon", "rules"] && pdf.entries.contains { $0.name == "Lairs" }
        }
    }

    @Test("A replaced file reaches the database and the game copy")
    func replaceFile() async throws {
        let fixture = try await makeFixture()
        let fileUrl = FileUrl(fileId: fixture.itemId, url: URL(filePath: "/Pdf/Rulebook.pdf"), location: .newCloud, module: "pdf", relativeUrl: nil)

        fixture.root.editController.reset(fileUrl: fileUrl, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.fileUrl == fileUrl }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        let bookmark = PdfEntryModel(id: UUID(), name: "Magic", content: "Spells", pageNumber: "40", bounds: .zero)
        fixture.root.editController.addBookmark(itemId: fixture.itemId, entry: bookmark, forceSave: true)

        fixture.root.editController.undo()
        try await fixture.expectEdit { $0.entries.map(\.id) == [fixture.entryId] }

        fixture.root.editController.redo()
        try await fixture.expectEdit { $0.entries.map(\.id) == [fixture.entryId, bookmark.id] }
    }

    @Test("An edit of a PDF the game has not loaded reaches the database and makes no game copy")
    func editOfPdfNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)
        let bookmark = PdfEntryModel(id: UUID(), name: "Magic", content: "Spells", pageNumber: "40", bounds: .zero)

        fixture.root.editController.addBookmark(itemId: fixture.itemId, entry: bookmark, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.entries.count == 2 }
    }

    @Test("Without the editor, an in-game bookmark stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()
        let bookmark = PdfEntryModel(id: UUID(), name: "Magic", content: "Spells", pageNumber: "40", bounds: .zero)

        fixture.root.editController.addBookmark(itemId: fixture.itemId, entry: bookmark)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.entries.count == 2 }
    }
}
#endif
