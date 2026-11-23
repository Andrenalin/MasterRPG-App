// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG

@Suite("Adventure table players")
@MainActor
struct AdventureTablePlayersTests {
    let tablePlayers = [
        TablePlayerModel(characterId: UUID()),
        TablePlayerModel(characterId: UUID(), isEnabled: false)
    ]

    func adventure(tablePlayers: [TablePlayerModel] = []) -> AdventureModel {
        AdventureModel(id: UUID(), name: "Journey", tablePlayers: tablePlayers)
    }

    @Test func codableRoundTrip() throws {
        let original = adventure(tablePlayers: tablePlayers)

        let decoded = try JSONDecoder().decode(AdventureModel.self, from: JSONEncoder().encode(original))

        #expect(decoded.tablePlayers == tablePlayers)
        #expect(decoded == original)
    }

    @Test func aFileWithoutTablePlayersDecodesToNone() throws {
        let data = try JSONEncoder().encode(adventure(tablePlayers: tablePlayers))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json.removeValue(forKey: "_tablePlayers_") != nil)

        let decoded = try JSONDecoder().decode(AdventureModel.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.tablePlayers.isEmpty)
    }

    @Test func aListThatWasNeverSetNeverWinsAMerge() throws {
        let local = adventure(tablePlayers: tablePlayers)
        // Decoded later than `local` was edited, as an import of an older file would be.
        let data = try JSONEncoder().encode(local)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["_tablePlayers_"] = nil
        let older = try JSONDecoder().decode(AdventureModel.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(local.merge(older).tablePlayers == tablePlayers)
        #expect(older.merge(local).tablePlayers == tablePlayers)
    }

    @Test func theLatestEditWinsAMergeEvenWhenItEmptiesTheList() {
        let local = adventure(tablePlayers: tablePlayers)
        let remote = local.copy()
        remote.tablePlayers = []

        #expect(local.merge(remote).tablePlayers.isEmpty)
        #expect(remote.merge(local).tablePlayers.isEmpty)
    }

    @Test func sameDuplicateAndReplace() {
        let original = adventure(tablePlayers: tablePlayers)
        let changed = original.copy()
        #expect(original.isSame(changed))

        changed.tablePlayers = [tablePlayers[0]]
        #expect(!original.isSame(changed))

        #expect(original.duplicate().tablePlayers == tablePlayers)

        #expect(original.replace(with: changed))
        #expect(original.tablePlayers == [tablePlayers[0]])
    }

    @Test func tablePlayersAreLinkedToTheirCharacters() {
        let old = adventure()
        let new = old.copy()
        new.tablePlayers = tablePlayers

        let (added, removed) = new.changedLinkRegisterModels(oldValue: old)

        #expect(Set(added.map(\.destination.itemId)) == Set(tablePlayers.map(\.characterId)))
        #expect(added.allSatisfy { $0.destination.typeId == .value })
        #expect(removed.isEmpty)
    }

    // CODE_AUDIT_28 §5.19
    @Test func diceSetIsLinkedAndUnlinked() {
        let diceId = UUID()
        let old = adventure()
        let new = old.copy()
        new.diceId = diceId

        let (added, removed) = new.changedLinkRegisterModels(oldValue: old)
        #expect(added.map(\.destination.itemId) == [diceId])
        #expect(added.allSatisfy { $0.destination.typeId == .dice })
        #expect(removed.isEmpty)

        let (added2, removed2) = old.changedLinkRegisterModels(oldValue: new)
        #expect(added2.isEmpty)
        #expect(removed2.map(\.destination.itemId) == [diceId])
    }

    @Test func registeredDiceLinkNamesTheAdventureAsAffected() {
        let diceId = UUID()
        let model = adventure()
        model.diceId = diceId

        #expect(model.linkRegisterModels.contains { $0.destination.itemId == diceId && $0.destination.typeId == .dice })
    }
}
#endif
