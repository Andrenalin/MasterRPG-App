// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import SpaceRPG

@MainActor
struct GameControllerTests {
    @Test func transformUpdateAndResetState() async throws {
        let root = SpaceRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let itemId = UUID()
        let item = SpaceModel(id: itemId, name: "Tower", displayState: 0)
        let transform = SpaceTransformModel(
            position: SIMD3<Float>(1, 2, 3),
            scale: SIMD3<Float>(2, 2, 2),
            yaw: 0.5,
            pitch: 0.25
        )

        root.itemController.replace(model: item, isInsert: true)
        sut.setGame(item: item.copy(), itemId: itemId)

        #expect(sut.currentItem().id == itemId)
        #expect(sut.gameItem(for: itemId).name == "Tower")

        try await sut.updateGame(
            data: NetworkCodableDataType(id: itemId, type: .space, version: 0, data: transform.encodeData()),
            subtype: .spaceTransform
        )
        #expect(sut.spaceGameModel.sharedTransform == transform)

        try await sut.updateGame(
            data: NetworkCodableDataType(id: itemId, type: .space, version: 0, data: nil),
            subtype: .generic
        )
        #expect(sut.spaceGameModel.sharedTransform == transform)

        sut.spaceGameModel.openSpace = true
        sut.resetGameState()
        #expect(!sut.spaceGameModel.openSpace)
        #expect(sut.spaceGameModel.sharedTransform == nil)
    }
}
