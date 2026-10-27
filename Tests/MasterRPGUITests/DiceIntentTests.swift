// @copyright André Trettin

import AppIntentsTesting
import XCTest

/// The Dice module's roll intents and its dice-type `AppEnum`. The create / query / delete round
/// trip is shared with the other modules in `ItemIntentTests`.
@available(iOS 27, macOS 27, *)
final class DiceIntentTests: AppIntentsUITestCase {
    private static let diceTypes = ["D4", "D6", "D8", "D10", "D12", "D20", "D100"]

    // MARK: Roll

    func testRollDiceRunsForEveryDiceType() async throws {
        for diceType in Self.diceTypes {
            try await definitions.intents["RollDiceIntent"].makeIntent(diceType: diceType).run()
        }
    }

    func testRollDiceDefaultsToATwentySidedDie() async throws {
        try await definitions.intents["RollDiceIntent"].makeIntent().run()
    }

    func testRollDiceAcceptsAnEnumCase() async throws {
        let diceType = definitions.enums["IntentDiceType"]
        XCTAssertEqual(diceType.typeIdentifier, "IntentDiceType")

        for rawValue in Self.diceTypes {
            let value = diceType.makeCase(rawValue)
            XCTAssertEqual(value.rawValue, rawValue)
            try await definitions.intents["RollDiceIntent"].makeIntent(diceType: value).run()
        }
    }

    func testRollDiceExpressionRunsForNotation() async throws {
        for expression in ["3d6+2", "2 W 20", "d20 plus 5"] {
            try await definitions.intents["RollDiceExpressionIntent"].makeIntent(expression: expression).run()
        }
    }

    func testShowDiceHistoryRunsAfterARoll() async throws {
        try await definitions.intents["RollDiceIntent"].makeIntent(diceType: "D6").run()
        try await definitions.intents["ShowDiceHistoryIntent"].makeIntent().run()
    }

    func testShowDiceHistoryRunsWithoutAnyRoll() async throws {
        // A fresh install has no last roll; the intent answers instead of failing.
        try await definitions.intents["ShowDiceHistoryIntent"].makeIntent().run()
    }

    // MARK: Dice sets

    func testRollSpecificDiceRollsACreatedSet() async throws {
        let (dice, _) = try await createItem(.dice)
        for _ in 0..<3 {
            try await definitions.intents["RollSpecificDiceIntent"].makeIntent(dice: dice).run()
        }
    }

    func testRollSpecificDiceFailsForADeletedSet() async throws {
        let (dice, _) = try await createItem(.dice)
        try await delete(.dice, [dice])

        do {
            try await definitions.intents["RollSpecificDiceIntent"].makeIntent(dice: dice).run()
            XCTFail("A deleted dice set must not be rolled.")
        } catch {
            // Expected.
        }
    }

    func testCreateDiceAcceptsEveryDiceType() async throws {
        for diceType in Self.diceTypes {
            let name = uniqueName("Dice \(diceType)")
            let result = try await definitions.intents["CreateDiceIntent"]
                .makeIntent(name: name, diceType: diceType, openWhenCreated: false)
                .run()
            let dice: AnyAppEntity = try result.value
            try await delete(.dice, [dice])
        }
    }

    func testAddDieToDiceRunsOnAReturnedEntity() async throws {
        let (dice, _) = try await createItem(.dice)
        for diceType in ["D4", "D12", "D100"] {
            try await definitions.intents["AddDieToDiceIntent"]
                .makeIntent(target: dice, diceType: diceType)
                .run()
        }

        let resolved = try await definitions.entities["DiceEntity"]
            .entities(identifiers: [dice.identifier.instanceIdentifier])
        XCTAssertEqual(resolved.count, 1)
    }

    func testAddDieToDiceFailsForADeletedSet() async throws {
        let (dice, _) = try await createItem(.dice)
        try await delete(.dice, [dice])

        do {
            try await definitions.intents["AddDieToDiceIntent"].makeIntent(target: dice, diceType: "D8").run()
            XCTFail("A die must not be added to a deleted dice set.")
        } catch {
            // Expected.
        }
    }
}
