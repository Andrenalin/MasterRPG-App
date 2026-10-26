// @copyright André Trettin

import AppIntentsTesting
import XCTest

/// The create / query / index / open / search / add / delete intents every item-backed content
/// module exposes, run against the real app. See `IntentModule` for the module table.
@available(iOS 27, macOS 27, *)
final class ItemIntentTests: AppIntentsUITestCase {
    // MARK: Create

    func testCreateReturnsTheNewEntity() async {
        await forEachModule { module in
            let details = "Created by the intent tests."
            let (entity, name) = try await createItem(module, details: details)

            XCTAssertFalse(entity.identifier.instanceIdentifier.isEmpty, module.name)
            XCTAssertEqual(entity.identifier.entityType.persistentIdentifier, module.entityType)
            XCTAssertEqual(try entity.name as String, name, module.name)
            XCTAssertEqual(try entity.description as String, details, module.name)
        }
    }

    func testCreateWithoutDetailsHasAnEmptyDescription() async {
        await forEachModule { module in
            let (entity, _) = try await createItem(module)
            XCTAssertEqual(try entity.description as String, "", module.name)
        }
    }

    // MARK: Entity queries

    func testStringQueryFindsTheItem() async {
        await forEachModule { module in
            let (entity, name) = try await createItem(module)
            let query = definitions.entities[module.entityType]

            let matches = try await query.entities(matching: name)
            XCTAssertEqual(identifiers(of: matches), [entity.identifier.instanceIdentifier], module.name)

            // `entities(matching:)` filters with `localizedStandardContains`.
            let lowercased = try await query.entities(matching: name.lowercased())
            XCTAssertEqual(identifiers(of: lowercased), [entity.identifier.instanceIdentifier], module.name)

            let unknown = try await query.entities(matching: "AIT no such item \(UUID().uuidString)")
            XCTAssertTrue(unknown.isEmpty, module.name)
        }
    }

    func testIdentifierQueryResolvesTheItem() async {
        await forEachModule { module in
            let (entity, name) = try await createItem(module)
            let id = entity.identifier.instanceIdentifier
            let query = definitions.entities[module.entityType]

            let resolved = try await query.entities(identifiers: [id])
            XCTAssertEqual(identifiers(of: resolved), [id], module.name)
            XCTAssertEqual(try resolved.first?.name as String?, name, module.name)

            let missing = try await query.entities(identifiers: [UUID().uuidString])
            XCTAssertTrue(missing.isEmpty, module.name)
        }
    }

    func testAllAndSuggestedQueriesAreServed() async {
        await forEachModule { module in
            let (entity, _) = try await createItem(module)
            let query = definitions.entities[module.entityType]

            let all = try await query.allEntities()
            XCTAssertTrue(identifiers(of: all).contains(entity.identifier.instanceIdentifier), module.name)

            // Suggestions are capped (`ItemEntityQuery.suggestedLimit`), so the new item may be cut.
            let suggested = try await query.suggestedEntities()
            XCTAssertLessThanOrEqual(suggested.count, 20, module.name)
        }
    }

    func testEmptyStringQueryFallsBackToSuggestions() async {
        await forEachModule { module in
            try await createItem(module)
            let query = definitions.entities[module.entityType]

            let matching = try await query.entities(matching: "")
            let suggested = try await query.suggestedEntities()
            XCTAssertEqual(identifiers(of: matching), identifiers(of: suggested), module.name)
        }
    }

    // MARK: Spotlight

    func testCreatedItemIsIndexedInSpotlight() async {
        await forEachModule { module in
            let name = uniqueName(module.name)
            let query = definitions.entities[module.entityType]
            let before = try await query.spotlightQuery(name)
            XCTAssertTrue(before.isEmpty, "\(module.name) was indexed before it existed.")

            let (entity, _) = try await createItem(module, name: name)

            try await eventually("\(module.name) was not indexed in Spotlight.") {
                let hits = try await query.spotlightQuery(name)
                return identifiers(of: hits).contains(entity.identifier.instanceIdentifier)
            }
        }
    }

    // MARK: Add content

    func testAddIntentAcceptsTheReturnedEntity() async {
        await forEachModule(IntentModule.all.filter { $0.addIntent != nil }) { module in
            let (entity, _) = try await createItem(module)
            let addIntent = try XCTUnwrap(module.addIntent)
            let value = module.addValueIsNote ? "A note from the intent tests." : "AIT section"

            // The entity returned by the create intent goes straight into the next intent, the way
            // a shortcut chains them.
            let arguments: KeyValuePairs<String, (any IntentValueExpressing)?> = [
                "target": entity,
                module.addParameter: value
            ]
            try await definitions.intents[addIntent].makeIntent
                .dynamicallyCall(withKeywordArguments: arguments)
                .run()

            // The item is still there and still resolvable afterwards.
            let resolved = try await definitions.entities[module.entityType]
                .entities(identifiers: [entity.identifier.instanceIdentifier])
            XCTAssertEqual(resolved.count, 1, module.name)
        }
    }

    // MARK: Open and search

    func testOpenIntentOpensTheItem() async {
        await forEachModule { module in
            let (entity, _) = try await createItem(module)
            try await definitions.intents[module.openIntent].makeIntent(target: entity).run()
        }
    }

    func testOpenIntentAcceptsAReferenceById() async {
        await forEachModule { module in
            let (entity, _) = try await createItem(module)
            let reference = definitions.entities[module.entityType]
                .makeReference(identifier: entity.identifier.instanceIdentifier)
            try await definitions.intents[module.openIntent].makeIntent(target: reference).run()
        }
    }

    func testSearchIntentRuns() async {
        await forEachModule { module in
            let (_, name) = try await createItem(module)
            try await definitions.intents[module.searchIntent].makeIntent(criteria: name).run()
        }
    }

    // MARK: Delete

    func testDeleteRemovesTheItemFromQueriesAndSpotlight() async {
        await forEachModule { module in
            let name = uniqueName(module.name)
            let (entity, _) = try await createItem(module, name: name)
            let id = entity.identifier.instanceIdentifier
            let query = definitions.entities[module.entityType]

            try await eventually("\(module.name) was not indexed in Spotlight.") {
                identifiers(of: try await query.spotlightQuery(name)).contains(id)
            }

            try await delete(module, [entity])

            // Trashed items must not resolve for Siri or Shortcuts any more.
            let byString = try await query.entities(matching: name)
            XCTAssertTrue(byString.isEmpty, "\(module.name) still matches by name.")
            let byIdentifier = try await query.entities(identifiers: [id])
            XCTAssertTrue(byIdentifier.isEmpty, "\(module.name) still resolves by identifier.")
            let all = try await query.allEntities()
            XCTAssertFalse(identifiers(of: all).contains(id), "\(module.name) is still listed.")

            try await eventually("\(module.name) is still in the Spotlight index.") {
                try await query.spotlightQuery(name).isEmpty
            }
        }
    }

    func testDeleteIntentTakesSeveralItems() async {
        await forEachModule { module in
            let (first, firstName) = try await createItem(module)
            let (second, secondName) = try await createItem(module)

            try await delete(module, [first, second])

            let query = definitions.entities[module.entityType]
            let remaining = try await query.allEntities()
            let ids = identifiers(of: remaining)
            XCTAssertFalse(ids.contains(first.identifier.instanceIdentifier), "\(module.name) \(firstName)")
            XCTAssertFalse(ids.contains(second.identifier.instanceIdentifier), "\(module.name) \(secondName)")
        }
    }
}
