// @copyright André Trettin

import AppIntents
import AppIntentsTesting
import XCTest

/// One content module's App Intents surface, addressed by type name.
///
/// `AppIntentsTesting` runs the real intents out of process, so this bundle never imports app
/// code: every intent, entity and parameter is a string that must match the declaration in the
/// module's `Intent/` folder. Renaming one of them fails these tests on purpose.
struct IntentModule: Sendable {
    let name: String
    let entityType: String
    let createIntent: String
    let openIntent: String
    let searchIntent: String
    let deleteIntent: String
    /// The optional rich-text parameter of the create intent (`story`, `instructions`, `details`).
    let detailsParameter: String
    /// The intent that appends content to an existing item, and the parameter that carries it.
    let addIntent: String?
    let addParameter: String
    /// `true` when `addParameter` is a required free-text note rather than a named child.
    let addValueIsNote: Bool
    /// The accessibility token of the module's list, see `MasterRPGUITestCase.openModule`.
    let listToken: String

    /// The iOS 27 `.system.open` sibling of `openIntent`, see CODE_AUDIT_AppIntents §4.2.
    var openSchemaIntent: String { String(openIntent.dropLast("Intent".count)) + "SchemaIntent" }

    static let adventure = IntentModule(
        name: "Adventure", entityType: "AdventureEntity",
        createIntent: "CreateAdventureIntent", openIntent: "OpenAdventureIntent",
        searchIntent: "SearchAdventuresIntent", deleteIntent: "DeleteAdventureIntent",
        detailsParameter: "story",
        addIntent: "AppendAdventureSectionIntent", addParameter: "sectionName", addValueIsNote: false,
        listToken: "ADVENTURES"
    )
    static let audio = IntentModule(
        name: "Audio", entityType: "AudioEntity",
        createIntent: "CreateAudioIntent", openIntent: "OpenAudioIntent",
        searchIntent: "SearchAudioIntent", deleteIntent: "DeleteAudioIntent",
        detailsParameter: "details",
        addIntent: "AddAudioNoteIntent", addParameter: "note", addValueIsNote: true,
        listToken: "AUDIOS"
    )
    static let character = IntentModule(
        name: "Character", entityType: "CharacterEntity",
        createIntent: "CreateCharacterIntent", openIntent: "OpenCharacterIntent",
        searchIntent: "SearchCharactersIntent", deleteIntent: "DeleteCharacterIntent",
        detailsParameter: "details",
        addIntent: "AddCharacterEntryIntent", addParameter: "entryName", addValueIsNote: false,
        listToken: "VALUES"
    )
    static let dice = IntentModule(
        name: "Dice", entityType: "DiceEntity",
        createIntent: "CreateDiceIntent", openIntent: "OpenDiceIntent",
        searchIntent: "SearchDiceIntent", deleteIntent: "DeleteDiceIntent",
        detailsParameter: "details",
        addIntent: nil, addParameter: "", addValueIsNote: false,
        listToken: "DICE"
    )
    static let generator = IntentModule(
        name: "Generator", entityType: "GeneratorEntity",
        createIntent: "CreateGeneratorIntent", openIntent: "OpenGeneratorIntent",
        searchIntent: "SearchGeneratorsIntent", deleteIntent: "DeleteGeneratorIntent",
        detailsParameter: "instructions",
        addIntent: "AddGeneratorNoteIntent", addParameter: "note", addValueIsNote: true,
        listToken: "GENERATOR"
    )
    static let map = IntentModule(
        name: "Map", entityType: "MapEntity",
        createIntent: "CreateMapIntent", openIntent: "OpenMapIntent",
        searchIntent: "SearchMapsIntent", deleteIntent: "DeleteMapIntent",
        detailsParameter: "details",
        addIntent: "AddMapRoomIntent", addParameter: "roomName", addValueIsNote: false,
        listToken: "MAPS"
    )
    static let pdf = IntentModule(
        name: "Pdf", entityType: "PdfEntity",
        createIntent: "CreatePdfIntent", openIntent: "OpenPdfIntent",
        searchIntent: "SearchPdfsIntent", deleteIntent: "DeletePdfIntent",
        detailsParameter: "details",
        addIntent: "AddPdfBookmarkIntent", addParameter: "bookmarkName", addValueIsNote: false,
        listToken: "PDFS"
    )
    static let photo = IntentModule(
        name: "Photo", entityType: "PhotoEntity",
        createIntent: "CreatePhotoIntent", openIntent: "OpenPhotoIntent",
        searchIntent: "SearchPhotosIntent", deleteIntent: "DeletePhotoIntent",
        detailsParameter: "details",
        addIntent: "AddPhotoNoteIntent", addParameter: "note", addValueIsNote: true,
        listToken: "PHOTOS"
    )
    static let rule = IntentModule(
        name: "Rule", entityType: "RuleEntity",
        createIntent: "CreateRuleIntent", openIntent: "OpenRuleIntent",
        searchIntent: "SearchRulesIntent", deleteIntent: "DeleteRuleIntent",
        detailsParameter: "details",
        addIntent: "AddRuleSectionIntent", addParameter: "sectionName", addValueIsNote: false,
        listToken: "RULES"
    )
    static let space = IntentModule(
        name: "Space", entityType: "SpaceEntity",
        createIntent: "CreateSpaceIntent", openIntent: "OpenSpaceIntent",
        searchIntent: "SearchSpacesIntent", deleteIntent: "DeleteSpaceIntent",
        detailsParameter: "details",
        addIntent: "AddSpaceNoteIntent", addParameter: "note", addValueIsNote: true,
        listToken: "SPACES"
    )
    static let table = IntentModule(
        name: "Table", entityType: "TableEntity",
        createIntent: "CreateTableIntent", openIntent: "OpenTableIntent",
        searchIntent: "SearchTablesIntent", deleteIntent: "DeleteTableIntent",
        detailsParameter: "details",
        addIntent: "AddTableRowIntent", addParameter: "rowName", addValueIsNote: false,
        listToken: "TABLES"
    )
    static let weather = IntentModule(
        name: "Weather", entityType: "WeatherEntity",
        createIntent: "CreateWeatherIntent", openIntent: "OpenWeatherIntent",
        searchIntent: "SearchWeatherIntent", deleteIntent: "DeleteWeatherIntent",
        detailsParameter: "details",
        addIntent: "AddWeatherNoteIntent", addParameter: "note", addValueIsNote: true,
        listToken: "WEATHERS"
    )

    static let all: [IntentModule] = [
        .adventure, .audio, .character, .dice, .generator, .map,
        .pdf, .photo, .rule, .space, .table, .weather
    ]
}

/// Base class of the out-of-process App Intents tests.
///
/// The app is launched once per test, then `definitions` drives the real intents across the
/// process boundary — the same path Siri and Shortcuts use. Tests are self-contained: they only
/// touch items they created under a unique name and delete them again in `tearDown`, so they
/// are safe on a simulator that already holds adventure data.
@available(iOS 27, macOS 27, *)
@MainActor
class AppIntentsUITestCase: MasterRPGUITestCase {
    static let bundleIdentifier = "de.AndreTrettin.GameMaster"

    private(set) var app: XCUIApplication!
    private(set) var definitions: IntentDefinitions!

    private var createdItems: [(module: IntentModule, entity: AnyAppEntity)] = []

    override func setUp() async throws {
        try await super.setUp()
        app = launchPreparedApp()
        // A failed module must not hide the remaining modules of a table-driven test.
        continueAfterFailure = true
        definitions = IntentDefinitions(bundleIdentifier: Self.bundleIdentifier)
    }

    override func tearDown() async throws {
        let leftovers = createdItems
        createdItems = []
        for (module, entity) in leftovers {
            _ = try? await definitions.intents[module.deleteIntent].makeIntent(entities: [entity]).run()
        }
        try await super.tearDown()
    }

    // MARK: Fixtures

    func uniqueName(_ prefix: String) -> String {
        "AIT \(prefix) \(UUID().uuidString.prefix(8))"
    }

    /// Creates an item through the module's real create intent, without opening it, and
    /// registers it for cleanup.
    @discardableResult
    func createItem(
        _ module: IntentModule,
        name: String? = nil,
        details: String? = nil
    ) async throws -> (entity: AnyAppEntity, name: String) {
        let itemName = name ?? uniqueName(module.name)
        // `makeIntent` is a dynamic callable; call it directly so the details parameter's name
        // can differ per module.
        var arguments: KeyValuePairs<String, (any IntentValueExpressing)?> = [
            "name": itemName,
            "openWhenCreated": false
        ]
        if let details {
            arguments = [
                "name": itemName,
                "openWhenCreated": false,
                module.detailsParameter: details
            ]
        }
        let intent = definitions.intents[module.createIntent].makeIntent.dynamicallyCall(withKeywordArguments: arguments)
        let result = try await intent.run()
        let entity: AnyAppEntity = try result.value
        createdItems.append((module, entity))
        return (entity, itemName)
    }

    func delete(_ module: IntentModule, _ entities: [AnyAppEntity]) async throws {
        try await definitions.intents[module.deleteIntent].makeIntent(entities: entities).run()
        let ids = entities.map(\.identifier.instanceIdentifier)
        createdItems.removeAll { ids.contains($0.entity.identifier.instanceIdentifier) }
    }

    // MARK: Table-driven tests

    /// Runs `body` for every module, reporting each failure under the module's name instead of
    /// stopping at the first broken one.
    func forEachModule(
        _ modules: [IntentModule] = IntentModule.all,
        _ body: (IntentModule) async throws -> Void
    ) async {
        for module in modules {
            do {
                try await body(module)
            } catch {
                XCTFail("\(module.name): \(error)")
            }
        }
    }

    // MARK: Assertions

    /// Polls until `condition` holds. Spotlight indexing is asynchronous, so the index trails the
    /// intent that wrote to it.
    func eventually(
        timeout: TimeInterval = 20,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async throws -> Bool
    ) async rethrows {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if try await condition() { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        XCTFail(message(), file: file, line: line)
    }

    /// Asserts that the intent asked for a value of `parameter` — what `needsValueError` raises.
    /// Out of process nobody can answer that prompt, so it surfaces as an execution error.
    func assertRequestsValue(
        forParameter parameter: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> some Any
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected the intent to request a value for '\(parameter)'.", file: file, line: line)
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("'\(parameter)'"),
                "Expected a request for '\(parameter)', got: \(error.localizedDescription)",
                file: file,
                line: line
            )
        }
    }

    func identifiers(of entities: [AnyAppEntity]) -> [String] {
        entities.map(\.identifier.instanceIdentifier)
    }
}
