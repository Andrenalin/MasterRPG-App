// @copyright André Trettin

#if canImport(Testing) && !os(tvOS)

import AppIntents
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

struct AudioAppIntentTests {
    @Test
    @MainActor
    func entityDisplayDataIsSafeAwayFromMainActor() async throws {
        let root = AudioRootModel.testRoot()
        let model = AudioModel(
            id: UUID(),
            name: "Battle Theme",
            description: "Looping combat music"
        )
        let entity = AudioEntity(root: root, model: model)

        let values = await Task.detached {
            _ = entity.displayRepresentation
            return (entity.name, entity.description, entity.icon)
        }.value

        #expect(values.0 == "Battle Theme")
        #expect(values.1 == "Looping combat music")
        #expect(values.2.isEmpty == false)
    }
}

#endif
