// @copyright André Trettin

import AppIntents
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

/// The root and the number of full entities built for `ProbeDiceQuery`, which `EntityQuery`
/// creates with `init()` and so cannot be handed a root.
@MainActor
private enum FindProbe {
    static var root: DiceRootModel?
    static var fullEntities = 0
}

/// `DiceEntityQuery` with a test root instead of the app's `@Dependency`, counting the full
/// entities it builds.
private struct ProbeDiceQuery: ItemEntityQuery {
    typealias Entity = DiceEntity

    nonisolated init() {}

    var root: DiceRootModel {
        guard let root = FindProbe.root else { fatalError("FindProbe.root is not set") }
        return root
    }

    func makeEntity(root: DiceRootModel, model: DiceModel) -> DiceEntity {
        FindProbe.fullEntities += 1
        return DiceEntity(root: root, model: model)
    }

    func makeFindEntity(root: DiceRootModel, model: DiceModel) -> DiceEntity {
        DiceEntity(root: root, model: model, includingText: false)
    }

    func allIds(root: DiceRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: DiceRootModel, id: UUID) -> DiceModel? { root.itemController.itemSync(for: id) }
}

/// CODE_AUDIT_Since_3.0.1 §7.2: the Find action built every entity, with its text excerpt, before
/// it checked the predicates and the limit.
@MainActor
@Suite("Find action", .serialized)
struct FindEntitiesTests {
    private func makeRoot(names: [String]) async -> DiceRootModel {
        let root = DiceRootModel.testRoot()
        for name in names {
            let id = await root.itemController.addNew(type: .item)
            root.editController.reset(name: name, itemId: id, forceSave: false)
        }
        FindProbe.root = root
        FindProbe.fullEntities = 0
        // The test root is loaded; without this `findEntities` waits out `DatabaseReadiness.timeout`.
        DatabaseReadiness.markReady()
        return root
    }

    @Test("Only the matches become full entities")
    func fullEntitiesOnlyForMatches() async throws {
        _ = await makeRoot(names: ["Goblin", "Orc", "Goblin King", "Troll"])
        let query = ProbeDiceQuery()
        let goblins = #Predicate<DiceEntity> { $0.name.localizedStandardContains("goblin") }

        let found = try await query.findEntities(matching: [goblins], mode: .and, nameAscending: true, name: { $0.name }, limit: nil)

        #expect(found.map(\.name) == ["Goblin", "Goblin King"])
        #expect(FindProbe.fullEntities == 2)
    }

    @Test("Sorting comes before the limit, and the limit caps the full entities")
    func sortThenLimit() async throws {
        _ = await makeRoot(names: ["Delta", "Alpha", "Charlie", "Bravo"])
        let query = ProbeDiceQuery()

        let found = try await query.findEntities(matching: [], mode: .and, nameAscending: false, name: { $0.name }, limit: 2)

        #expect(found.map(\.name) == ["Delta", "Charlie"])
        #expect(FindProbe.fullEntities == 2)
    }

    @Test("Without sorting the scan stops at the limit and keeps the item order")
    func unsortedStopsAtLimit() async throws {
        let root = await makeRoot(names: ["One", "Two", "Three"])
        let query = ProbeDiceQuery()
        let firstTwo = root.itemController.itemDataModel.items.prefix(2)

        let found = try await query.findEntities(matching: [], mode: .or, nameAscending: nil, name: { $0.name }, limit: 2)

        #expect(found.map(\.id) == Array(firstTwo))
        #expect(FindProbe.fullEntities == 2)
    }

    @Test("The light entity has no excerpt or subtitle, the full one has its subtitle")
    func lightEntity() async throws {
        let root = await makeRoot(names: ["Goblin"])
        let id = try #require(root.itemController.itemDataModel.items.first)
        let model = try #require(root.itemController.itemSync(for: id))
        model.description = "Small and mean"

        let light = DiceEntity(root: root, model: model, includingText: false)
        let full = DiceEntity(root: root, model: model)

        #expect(light.name == "Goblin")
        #expect(light.description == "Small and mean")
        #expect(light.subtitle.isEmpty)
        #expect(light.content.isEmpty)
        #expect(full.subtitle == "Small and mean")
    }
}
