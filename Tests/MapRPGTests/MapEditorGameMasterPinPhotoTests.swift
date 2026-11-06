// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@Suite("Game master pin photo")
@MainActor
struct MapEditorGameMasterPinPhotoTests {
    @Test("A double tap shows the photo to everyone and clears every other shared photo")
    func doubleTapSharesOnePhoto() throws {
        let firstId = UUID()
        let secondId = UUID()
        let fixture = makeFixture(pins: [
            MapPinModel(id: firstId, name: "First", isShown: true, timeInterval: 1, isPhotoShared: true),
            MapPinModel(id: secondId, name: "Second", isShown: true, timeInterval: 1)
        ])
        let second = try #require(fixture.session.pins.pinNode(for: secondId))

        second.handleDoubleTap()

        let pins = fixture.liveMap.mapPins
        #expect(pins.first { $0.id == firstId }?.isPhotoShared == false)
        #expect(pins.first { $0.id == secondId }?.isPhotoShared == true)
        #expect(fixture.broadcasts.count == 1)
        #expect(fixture.session.pins.photoPinId == secondId)
        // The session's pins follow the cleared one too.
        #expect(fixture.session.pins.pinNode(for: firstId)?.pin.isPhotoShared == false)

        // The second double tap closes it for everyone.
        second.handleDoubleTap()

        #expect(fixture.liveMap.mapPins.allSatisfy { !$0.isPhotoShared })
        #expect(fixture.broadcasts.count == 2)
        #expect(fixture.session.pins.photoPinId == nil)
    }

    @Test("Dismissing a shared photo closes it for the players too")
    func dismissUnsharesPhoto() throws {
        let pinId = UUID()
        let fixture = makeFixture(pins: [MapPinModel(id: pinId, name: "Pin", isShown: true)])
        try #require(fixture.session.pins.pinNode(for: pinId)).handleDoubleTap()
        #expect(fixture.liveMap.mapPins.first?.isPhotoShared == true)

        fixture.session.route(.dismissPinPhoto)

        #expect(fixture.liveMap.mapPins.first?.isPhotoShared == false)
        #expect(fixture.session.pins.photoPinId == nil)
        #expect(fixture.broadcasts.count == 2)
    }

    @Test("A hidden pin's photo stays on the game master's device")
    func hiddenPinPhotoIsLocal() throws {
        let pinId = UUID()
        let fixture = makeFixture(pins: [MapPinModel(id: pinId, name: "Ambush", isShown: false)])

        try #require(fixture.session.pins.pinNode(for: pinId)).handleDoubleTap()

        #expect(fixture.session.pins.photoPinId == pinId)
        #expect(fixture.liveMap.mapPins.first?.isPhotoShared == false)
        #expect(fixture.broadcasts.isEmpty)
    }

    private func makeFixture(pins: [MapPinModel]) -> Fixture {
        let persistentMap = MapModel(id: MapModel.previewId, name: "GM map", mapPins: pins)
        let root = MapRootModel.previewFixture(models: [persistentMap])
        let liveMap = root.gameController.gameItem(for: persistentMap.id)
        let recorder = BroadcastRecorder()
        let session = MapEditorSession(
            map: liveMap,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 800, height: 600),
            configuration: MapEditorConfiguration(mode: .gameMaster, displayMode: .master),
            actions: MapEditorActions(sendMapUpdates: { recorder.count += 1 })
        )
        session.installActionRouter(
            MapEditorActionRouter(
                session: session,
                editController: root.editController,
                mapEditController: MapEditController(editController: root.editController),
                map: liveMap,
                root: root
            )
        )
        return Fixture(liveMap: liveMap, session: session, recorder: recorder)
    }

    @MainActor
    private final class BroadcastRecorder {
        var count = 0
    }

    @MainActor
    private struct Fixture {
        let liveMap: MapModel
        let session: MapEditorSession
        let recorder: BroadcastRecorder
        var broadcasts: [Int] { Array(repeating: 0, count: recorder.count) }
    }
}
#endif
