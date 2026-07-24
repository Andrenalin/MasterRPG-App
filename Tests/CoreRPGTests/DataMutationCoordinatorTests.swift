// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
@Suite("Exclusive RPG data mutation")
struct DataMutationCoordinatorTests {
    @Test("Only one owner can mutate at a time")
    func excludesConcurrentOwners() throws {
        let coordinator = DataMutationCoordinator()
        let firstToken = try #require(coordinator.begin())

        #expect(coordinator.isActive)
        #expect(coordinator.begin() == nil)

        coordinator.end(UUID())
        #expect(coordinator.isActive)
        #expect(coordinator.begin() == nil)

        coordinator.end(firstToken)
        #expect(!coordinator.isActive)

        let nextToken = try #require(coordinator.begin())
        #expect(nextToken != firstToken)
        coordinator.end(nextToken)
        #expect(!coordinator.isActive)
    }
}
