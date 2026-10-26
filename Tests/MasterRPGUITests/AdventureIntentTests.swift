// @copyright André Trettin

import AppIntentsTesting
import XCTest

/// Behavior that only the Adventure intents have: input validation, starting a game, and the
/// on-screen annotation of an opened adventure. The create / query / delete round trip is shared
/// with the other modules in `ItemIntentTests`.
@available(iOS 27, macOS 27, *)
final class AdventureIntentTests: AppIntentsUITestCase {
    private var adventures: AppEntityDefinition { definitions.entities["AdventureEntity"] }

    // MARK: Input validation

    func testCreateWithBlankNameRequestsAName() async {
        for blank in ["", "   ", "\n"] {
            await assertRequestsValue(forParameter: "name") {
                try await definitions.intents["CreateAdventureIntent"]
                    .makeIntent(name: blank, openWhenCreated: false)
                    .run()
            }
        }
    }

    func testCreateTrimsTheName() async throws {
        let name = uniqueName("Trim")
        let (entity, _) = try await createItem(.adventure, name: "  \(name)  ")
        XCTAssertEqual(try entity.name as String, name)
    }

    func testAppendWithBlankSectionNameRequestsAName() async throws {
        let (adventure, _) = try await createItem(.adventure)
        await assertRequestsValue(forParameter: "sectionName") {
            try await definitions.intents["AppendAdventureSectionIntent"]
                .makeIntent(target: adventure, sectionName: "  ")
                .run()
        }
    }

    func testAppendToADeletedAdventureFails() async throws {
        let (adventure, _) = try await createItem(.adventure)
        try await delete(.adventure, [adventure])

        do {
            try await definitions.intents["AppendAdventureSectionIntent"]
                .makeIntent(target: adventure, sectionName: "Orphan")
                .run()
            XCTFail("Appending to a deleted adventure must not succeed.")
        } catch {
            // Either the entity no longer resolves or the intent asks for a new target.
        }
    }

    func testStartGameForADeletedAdventureFails() async throws {
        let (adventure, _) = try await createItem(.adventure)
        try await delete(.adventure, [adventure])

        do {
            try await definitions.intents["StartAdventureGameIntent"].makeIntent(target: adventure).run()
            XCTFail("A game must not start for a deleted adventure.")
        } catch {
            // Expected.
        }
    }

    // MARK: Game and navigation

    func testStartGameRunsForAnAdventure() async throws {
        let (adventure, _) = try await createItem(.adventure, details: "Story for the game start test.")
        try await definitions.intents["StartAdventureGameIntent"].makeIntent(target: adventure).run()

        await eventually("Starting the game did not select the Game tab.") {
            app.descendants(matching: .any)
                .matching(identifier: "module.tab.GAME")
                .firstMatch
                .isSelected
        }
    }

    func testOpeningAnAdventureAnnotatesItOnScreen() async throws {
        let (adventure, _) = try await createItem(.adventure)
        let id = adventure.identifier.instanceIdentifier

        try await definitions.intents["OpenAdventureIntent"].makeIntent(target: adventure).run()

        try await eventually("The opened adventure is not reported as on screen.") {
            identifiers(of: try await adventures.viewAnnotations().map(\.entity)).contains(id)
        }
    }

    // MARK: Chaining

    func testCreateThenAppendThenDeleteChains() async throws {
        let (adventure, name) = try await createItem(.adventure, details: "Chained")

        try await definitions.intents["AppendAdventureSectionIntent"]
            .makeIntent(target: adventure, sectionName: "Chapter 1", content: "It begins.")
            .run()
        try await definitions.intents["OpenAdventureIntent"].makeIntent(target: adventure).run()
        try await delete(.adventure, [adventure])

        let remaining = try await adventures.entities(matching: name)
        XCTAssertTrue(remaining.isEmpty)
    }
}
