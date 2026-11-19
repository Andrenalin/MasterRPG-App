// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT_TestGaps §6.3: what the share extension writes. The extension runs in its own
/// memory-limited process with no UI for errors, so a wrong save is lost silently. These tests run
/// the real controller against an in-memory store holding the full model of every module.
@MainActor
@Suite("Share extension save")
struct ShareExtensionSaveTests {
    private struct Fixture {
        let persistence: CoreDataPersistenceController
        let context: NSManagedObjectContext
        let controller: ShareExtensionSaveController
    }

    private func makeFixture() async throws -> Fixture {
        let persistence = CoreDataPersistenceController(inMemory: true, currentActor: .sharingExtension)
        persistence.loadDatabase(bundles: DataBaseModel.rpgModuleBundles)
        let loaded = await awaitCondition { persistence.model.context != nil }
        try #require(loaded, "the in-memory store did not load, error: \(persistence.model.error)")
        let context = try #require(persistence.model.context)
        let service = ShareExtensionDatabaseService(context: context, container: persistence.model.container)
        return Fixture(persistence: persistence, context: context, controller: ShareExtensionSaveController(databaseService: service))
    }

    private func count(_ entity: String, in context: NSManagedObjectContext) async throws -> Int {
        try await context.perform {
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity))
        }
    }

    /// The stored name of every row. The name is kept as a CRDT value, so its stored form is
    /// returned as text and a test checks what it contains.
    private func storedNames(_ entity: String, in context: NSManagedObjectContext) async throws -> [String] {
        try await context.perform {
            let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))
            return rows.map { row in
                switch row.value(forKey: "name") {
                case let text as String: text
                case let data as Data: String(decoding: data, as: UTF8.self)
                default: ""
                }
            }
        }
    }

    /// A tiny valid PNG.
    private static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    // MARK: - Text only

    @Test("A text share creates one item in the chosen module, with the name trimmed",
          arguments: [
            ("RPGAdventure", NetworkModules.adventure),
            ("RPGMap", .map),
            ("RPGWeather", .weather),
            ("RPGValue", .value)
          ])
    func textShareCreatesOneItem(entity: String, module: NetworkModules) async throws {
        let fixture = try await makeFixture()
        defer { fixture.persistence.model.stop() }

        try await fixture.controller.saveContent(to: module, name: "  Shared note  ", text: "Body", images: [])

        #expect(try await count(entity, in: fixture.context) == 1)
        let stored = try #require(try await storedNames(entity, in: fixture.context).first)
        #expect(stored.contains("Shared note"))
        #expect(!stored.contains("  Shared note"), "the name is trimmed before it is saved")
        #expect(!fixture.context.hasChanges, "the item must be saved, not only inserted")
    }

    @Test("Two shares create two items")
    func twoSharesCreateTwoItems() async throws {
        let fixture = try await makeFixture()
        defer { fixture.persistence.model.stop() }

        try await fixture.controller.saveContent(to: .adventure, name: "One", text: "", images: [])
        try await fixture.controller.saveContent(to: .adventure, name: "Two", text: "", images: [])

        let stored = try await storedNames("RPGAdventure", in: fixture.context)
        #expect(stored.count == 2)
        #expect(stored.contains { $0.contains("One") })
        #expect(stored.contains { $0.contains("Two") })
    }

    // MARK: - Refusals

    @Test("Photo without an image saves nothing and says so")
    func photoNeedsAnImage() async throws {
        let fixture = try await makeFixture()
        defer { fixture.persistence.model.stop() }

        await #expect(throws: ShareExtensionError.self) {
            try await fixture.controller.saveContent(to: .photo, name: "Nothing", text: "Text", images: [])
        }

        #expect(try await count("RPGPhoto", in: fixture.context) == 0)
        #expect(!fixture.context.hasChanges)
    }

    @Test("A module the extension cannot save into is refused and leaves nothing behind", arguments: [
        NetworkModules.audio, .dice, .table, .pdf
    ])
    func unsupportedModuleIsRefused(module: NetworkModules) async throws {
        let fixture = try await makeFixture()
        defer { fixture.persistence.model.stop() }

        do {
            try await fixture.controller.saveContent(to: module, name: "Nope", text: "", images: [])
            Issue.record("\(module) must not be savable")
        } catch let error as ShareExtensionError {
            guard case .moduleNotSupported = error else {
                Issue.record("Expected moduleNotSupported, got \(error)")
                return
            }
        }

        #expect(!fixture.context.hasChanges)
    }

    @Test("A service without a context cannot save")
    func missingContextIsRefused() async throws {
        let controller = ShareExtensionSaveController(databaseService: ShareExtensionDatabaseService())

        do {
            try await controller.saveContent(to: .adventure, name: "x", text: "", images: [])
            Issue.record("a service that never ran setup() must refuse")
        } catch let error as ShareExtensionError {
            guard case .contextNotAvailable = error else {
                Issue.record("Expected contextNotAvailable, got \(error)")
                return
            }
        }
    }

    // MARK: - With images

    @Test("A failing save after the photo files were written removes the rows again")
    func failedSaveRollsBack() async throws {
        let fixture = try await makeFixture()
        defer { fixture.persistence.model.stop() }

        // Photos are written first, then the unsupported module is refused.
        do {
            try await fixture.controller.saveContent(to: .audio, name: "Rollback", text: "", images: [Self.pngData])
            Issue.record("the unsupported module must fail the save")
        } catch {
            // A storage failure while writing the photo is a failure of the same kind.
        }

        #expect(try await count("RPGPhoto", in: fixture.context) == 0, "no row may remain for a failed save")
        #expect(!fixture.context.hasChanges)
    }
}
#endif
