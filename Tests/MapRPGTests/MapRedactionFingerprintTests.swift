// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_26 §10.15, next to `MapWallRedactionTests` and `MapPinVisibilityTests`: what the
/// player copy blanks and what the content fingerprint follows.
@MainActor
struct MapRedactionFingerprintTests {
    private let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]

    @Test func hiddenRoomTextIsBlankedForPlayersButShownRoomsAndTheMasterCopyKeepTheirs() {
        // Given
        let hidden = MapEntryModel(id: UUID(), name: "Crypt", content: "Secret", coordinates: square, isShown: false)
        let shown = MapEntryModel(id: UUID(), name: "Hall", content: "Open", coordinates: square, isShown: true)
        let map = MapModel(id: UUID(), name: "Map", entries: [hidden, shown])

        // When
        let player = MapSnapshot(map).redactedForNonMaster().entries.wrappedValue
        let master = MapSnapshot(map).entries.wrappedValue

        // Then
        #expect(player.first { $0.id == hidden.id }?.name.isEmpty == true)
        #expect(player.first { $0.id == hidden.id }?.content.isEmpty == true)
        #expect(player.first { $0.id == shown.id }?.name == "Hall")
        #expect(player.first { $0.id == shown.id }?.content == "Open")
        #expect(master.first { $0.id == hidden.id }?.content == "Secret")
    }

    @Test func contentVersionHelperMatchesThePayloadFingerprint() {
        // Given
        let room = MapEntryModel(id: UUID(), name: "Crypt", content: "Secret", coordinates: square, isShown: false)
        let map = MapModel(id: UUID(), name: "Map", entries: [room])

        // Then
        #expect(MapUpdatePayload.contentVersion(of: map) == MapUpdatePayload(model: map).contentVersion)
    }

    @Test func editingHiddenRoomTextMovesTheFingerprintWhileThePlayerCopyStaysBlank() {
        // Given
        let room = MapEntryModel(id: UUID(), name: "Crypt", content: "Secret", coordinates: square, isShown: false)
        let map = MapModel(id: UUID(), name: "Map", entries: [room])
        let before = MapUpdatePayload(model: map)

        // When
        var edited = room
        edited.content = "A different secret"
        map.entries = [edited]
        let after = MapUpdatePayload(model: map)

        // Then: the master's real state is what the fingerprint follows, so a later reveal registers
        #expect(before.contentVersion != after.contentVersion)
        #expect(after.snapshot.entries.wrappedValue.first?.content.isEmpty == true)
    }
}
#endif
