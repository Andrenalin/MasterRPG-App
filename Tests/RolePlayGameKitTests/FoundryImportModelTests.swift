// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT_TestGaps §5.7: the load state machine of the Foundry / Universal VTT import
/// screen: what a selection resets, how a file is classified, and that a stale or cancelled
/// load never touches the current selection. The registry and the archive store point at a
/// temporary folder, so nothing of the user's library is read or written.
@MainActor
@Suite("Foundry import model")
struct FoundryImportModelTests {
    /// A temporary folder that is removed when the test ends.
    private final class Folder {
        let url: URL

        init() throws {
            url = URL.temporaryDirectory.appending(path: "FoundryImportModel-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func write(_ name: String, _ data: Data) throws -> URL {
            let file = url.appending(path: name)
            try data.write(to: file)
            return file
        }
    }

    private func makeModel(in folder: Folder) -> FoundryImportModel {
        FoundryImportModel(
            archiveStore: FoundryImportArchiveStore(directoryURL: folder.url.appending(path: "Archives", directoryHint: .isDirectory)),
            sourceRegistry: ExternalImportSourceRegistry(directoryURL: folder.url.appending(path: "Registry", directoryHint: .isDirectory))
        )
    }

    private func universalVTT(_ folder: Folder, name: String = "dungeon.uvtt", pixelsPerGrid: Int = 50) throws -> URL {
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).base64EncodedString()
        let json = ##"{"resolution":{"map_origin":{"x":0,"y":0},"map_size":{"x":20,"y":10},"pixels_per_grid":\##(pixelsPerGrid)},"line_of_sight":[],"portals":[],"lights":[],"image":"\##(png)"}"##
        return try folder.write(name, Data(json.utf8))
    }

    // MARK: - Selection

    @Test("A new model has nothing selected and offers neither review nor another source")
    func startsEmpty() {
        let model = FoundryImportModel()

        #expect(model.loadState == .notStarted)
        #expect(model.selectedUrl == nil)
        #expect(!model.canPrepareReview)
        #expect(!model.isWorking)
        #expect(!model.canChooseAnotherSource)
        #expect(model.selectedCategories == FoundryImportCategory.privacySafeDefaults)
    }

    @Test("Selecting a file resets everything of an earlier one and starts a new selection")
    func selectResets() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        let first = try universalVTT(folder, name: "first.uvtt")
        #expect(model.select(url: first))
        await model.loadSelectedArtifact()
        #expect(model.universalVTT != nil)
        model.toggle(.macros)
        let firstSelection = model.selectionId

        let second = try universalVTT(folder, name: "second.uvtt")
        #expect(model.select(url: second))

        #expect(model.selectedUrl == second)
        #expect(model.selectionId != firstSelection)
        #expect(model.artifact == nil)
        #expect(model.universalVTT == nil)
        #expect(model.package == nil)
        #expect(model.sourceResolution == nil)
        #expect(!model.canPrepareReview)
        #expect(model.selectedCategories == FoundryImportCategory.privacySafeDefaults, "the toggles of the old file do not carry over")
    }

    // CODE_AUDIT_28 §5.21
    @Test("Loading again after the view re-appears keeps the loaded state and reads nothing")
    func reloadingIsANoOp() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        let url = try universalVTT(folder)
        _ = model.select(url: url)
        await model.loadSelectedArtifact()
        #expect(model.loadState == .preflight)
        try FileManager.default.removeItem(at: url)

        await model.loadSelectedArtifact()

        #expect(model.loadState == .preflight)
        #expect(model.universalVTT != nil)
    }

    @Test("A failed load starts again with a new selection")
    func failedLoadRetriesWithNewSelection() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        _ = model.select(url: folder.url.appending(path: "missing.uvtt"))
        await model.loadSelectedArtifact()
        guard case .failed = model.loadState else {
            Issue.record("expected a failure, got \(model.loadState)")
            return
        }

        _ = model.select(url: try universalVTT(folder))
        await model.loadSelectedArtifact()

        #expect(model.loadState == .preflight)
    }

    @Test("Loading without a selection does nothing")
    func loadWithoutSelection() async {
        let model = FoundryImportModel()

        await model.loadSelectedArtifact()

        #expect(model.loadState == .notStarted)
    }

    // MARK: - Load

    @Test("A Universal VTT file loads to the preflight with a source that is already resolved")
    func universalVTTLoads() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        _ = model.select(url: try universalVTT(folder))

        await model.loadSelectedArtifact()

        #expect(model.loadState == .preflight)
        #expect(model.artifact?.kind == .universalVTT)
        #expect(model.universalVTT?.resolution.pixelsPerGrid == 50)
        #expect(model.package == nil)
        guard case .resolved(let scopeId) = model.sourceResolution else {
            Issue.record("A file never imported before resolves to a new source, got \(String(describing: model.sourceResolution))")
            return
        }
        #expect(model.selectedSourceScopeId == scopeId)
        #expect(model.canPrepareReview)
        #expect(model.canChooseAnotherSource)
        #expect(!model.isWorking)
    }

    @Test("A file of an unknown kind fails with a message and can be replaced")
    func unknownFileFails() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        _ = model.select(url: try folder.write("notes.txt", Data("not a foundry file".utf8)))

        await model.loadSelectedArtifact()

        guard case .failed(let message) = model.loadState else {
            Issue.record("Expected failed, got \(model.loadState)")
            return
        }
        #expect(!message.isEmpty)
        #expect(model.canChooseAnotherSource)
        #expect(!model.canPrepareReview)
        #expect(model.select(url: try universalVTT(folder)), "a failed load does not lock the selection")
    }

    @Test("A Universal VTT file with an invalid resolution fails the load")
    func invalidUniversalVTTFails() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        _ = model.select(url: try universalVTT(folder, pixelsPerGrid: 0))

        await model.loadSelectedArtifact()

        guard case .failed = model.loadState else {
            Issue.record("Expected failed, got \(model.loadState)")
            return
        }
        #expect(model.universalVTT == nil)
        #expect(model.selectedSourceScopeId == nil)
    }

    @Test("A missing file fails the load")
    func missingFileFails() async {
        let model = FoundryImportModel()
        _ = model.select(url: URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).uvtt"))

        await model.loadSelectedArtifact()

        guard case .failed = model.loadState else {
            Issue.record("Expected failed, got \(model.loadState)")
            return
        }
    }

    @Test("A load that was replaced by a newer selection leaves the newer one alone")
    func staleLoadIsIgnored() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        let first = try universalVTT(folder, name: "first.uvtt")
        let second = try universalVTT(folder, name: "second.uvtt", pixelsPerGrid: 70)
        _ = model.select(url: first)

        let firstLoad = Task { await model.loadSelectedArtifact() }
        await Task.yield() // the first load is under way
        _ = model.select(url: second)
        await firstLoad.value

        #expect(model.selectedUrl == second)
        // Whatever the interleaving, the first file's data must not be stored for the second.
        #expect(model.universalVTT == nil || model.universalVTT?.resolution.pixelsPerGrid == 70)
        #expect(model.universalVTT?.resolution.pixelsPerGrid != 50)

        await model.loadSelectedArtifact()
        #expect(model.loadState == .preflight)
        #expect(model.universalVTT?.resolution.pixelsPerGrid == 70)
    }

    @Test("A cancelled load goes back to not started")
    func cancelledLoadGoesBack() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        _ = model.select(url: try universalVTT(folder))

        let load = Task { await model.loadSelectedArtifact() }
        load.cancel()
        await load.value

        #expect(model.loadState == .notStarted || model.loadState == .preflight, "cancelled before or after the work")
        #expect(!model.isWorking)
        if model.loadState == .notStarted {
            #expect(model.selectedSourceScopeId == nil)
        }
    }

    // MARK: - Categories

    @Test("A category is switched on and off by toggling")
    func toggleCategory() {
        let model = FoundryImportModel()
        let category = FoundryImportCategory.macros
        let before = model.selectedCategories.contains(category)

        model.toggle(category)
        #expect(model.selectedCategories.contains(category) != before)
        model.toggle(category)
        #expect(model.selectedCategories.contains(category) == before)
    }

    @Test("The privacy-safe defaults leave out only users and chat")
    func privacySafeDefaults() {
        let defaults = FoundryImportCategory.privacySafeDefaults

        #expect(!defaults.contains(.users))
        #expect(!defaults.contains(.chat))
        #expect(defaults.count == FoundryImportCategory.allCases.count - 2)
    }

    // MARK: - Source choice

    @Test("Choosing a source is ignored while the source is already resolved")
    func sourceChoiceNeedsAnAmbiguousSource() async throws {
        let folder = try Folder()
        let model = makeModel(in: folder)
        _ = model.select(url: try universalVTT(folder))
        await model.loadSelectedArtifact()
        let resolved = model.selectedSourceScopeId

        model.chooseNewSource()
        model.chooseExistingSource(scopeID: UUID())

        #expect(model.selectedSourceScopeId == resolved)
    }

    // MARK: - Errors

    @Test("A selection error clears the selection and shows the message")
    func selectionError() async throws {
        struct PickerFailure: LocalizedError { var errorDescription: String? { "The picker failed" } }
        let folder = try Folder()
        let model = makeModel(in: folder)
        _ = model.select(url: try universalVTT(folder))
        await model.loadSelectedArtifact()

        model.reportSelectionError(PickerFailure())

        #expect(model.loadState == .failed("The picker failed"))
        #expect(model.selectedUrl == nil)
        #expect(model.universalVTT == nil)
        #expect(!model.canPrepareReview)
    }

    @Test("Preparing a review without a chosen source fails instead of guessing")
    func reviewNeedsASource() async {
        let model = FoundryImportModel()

        await model.prepareReview(rootManager: AppModel.previewWithoutDatabase.root)

        guard case .failed = model.loadState else {
            Issue.record("Expected failed, got \(model.loadState)")
            return
        }
        #expect(model.reviewSession == nil)
    }
}
#endif
