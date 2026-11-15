// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// The player copy of a map keeps wall geometry but not what the game master hid in it.
/// See CODE_AUDIT §6.1.
@MainActor
struct MapWallRedactionTests {
    private func wall(
        _ key: String,
        doorType: MapWallModel.DoorType = .none,
        doorState: MapWallModel.DoorState = .closed,
        metadata: FoundryJSONValue? = nil
    ) -> MapWallModel {
        MapWallModel(
            sourceIdentifier: key,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 100, y: 0),
            doorType: doorType,
            doorState: doorState,
            rawMetadata: metadata
        )
    }

    @Test func secretDoorIsSentAsAPlainWall() {
        // Given
        let secret = wall("secret", doorType: .secret, doorState: .locked)

        // When
        let redacted = secret.redactedForPlayers()

        // Then
        #expect(redacted.doorType == .none)
        #expect(redacted.doorState == .closed)
        #expect(redacted.id == secret.id)
        #expect(redacted.start == secret.start)
        #expect(redacted.end == secret.end)
        #expect(redacted.movementRestriction == secret.movementRestriction)
    }

    @Test func ordinaryDoorKeepsItsStateButLosesImportedMetadata() {
        // Given
        let door = wall("door", doorType: .door, doorState: .open, metadata: .string("gm note"))

        // When
        let redacted = door.redactedForPlayers()

        // Then
        #expect(redacted.doorType == .door)
        #expect(redacted.doorState == .open)
        #expect(redacted.rawMetadata == nil)
    }

    @Test func playerSnapshotRedactsWallsButKeepsTheMasterCopy() {
        // Given
        let secret = wall("secret", doorType: .secret, metadata: .string("flag"))
        let plain = wall("plain")
        let map = MapModel(id: UUID(), name: "Map")
        map.walls = [secret, plain]

        // When
        let player = MapSnapshot(map).redactedForNonMaster().walls.wrappedValue
        let master = MapSnapshot(map).walls.wrappedValue

        // Then
        #expect(player.map(\.id) == [secret.id, plain.id])
        #expect(player.allSatisfy { $0.doorType == .none && $0.rawMetadata == nil })
        #expect(master.first?.doorType == .secret)
        #expect(master.first?.rawMetadata == .string("flag"))
    }

    @Test func redactionDoesNotChangeTheMasterContentFingerprint() {
        // Given
        let map = MapModel(id: UUID(), name: "Map")
        map.walls = [wall("secret", doorType: .secret)]
        let before = MapUpdatePayload(model: map).contentVersion

        // When
        map.walls = [wall("secret", doorType: .none)]
        let after = MapUpdatePayload(model: map).contentVersion

        // Then: the master's fingerprint follows the real walls, so a GM edit still resends.
        #expect(before != after)
    }

    /// CODE_AUDIT_26 §6.7: the notes field and the tags are the game master's own.
    @Test func playerSnapshotBlanksDescriptionAndTagsButKeepsTheName() {
        // Given
        let map = MapModel(id: UUID(), name: "Crypt", description: "Secret door behind the altar", tags: ["spoiler"])

        // When
        let player = MapSnapshot(map).redactedForNonMaster()
        let master = MapSnapshot(map)

        // Then
        #expect(player.name.wrappedValue == "Crypt")
        #expect(player.description.wrappedValue.isEmpty)
        #expect(player.tags.wrappedValue.isEmpty)
        #expect(master.description.wrappedValue == "Secret door behind the altar")
        #expect(master.tags.wrappedValue == ["spoiler"])
    }
}
#endif
