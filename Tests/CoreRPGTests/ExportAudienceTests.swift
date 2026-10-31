// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

@Suite("Export audience")
struct ExportAudienceTests {
    @Test("an export is for its owner unless a player package is being built")
    func defaultsToOwner() {
        #expect(!ExportAudience.isPlayerPackage)

        ExportAudience.$current.withValue(.players) {
            #expect(ExportAudience.isPlayerPackage)
        }

        #expect(!ExportAudience.isPlayerPackage)
    }

    @Test("the audience reaches work the export starts in child tasks")
    func reachesChildTasks() async {
        let seen = await ExportAudience.$current.withValue(.players) {
            async let child = ExportAudience.isPlayerPackage
            let unstructured = await Task { ExportAudience.isPlayerPackage }.value
            return await (child, unstructured)
        }

        #expect(seen.0)
        #expect(seen.1)
    }

    @Test("the audience does not leak into a detached task, which the export must not use")
    func detachedTaskDoesNotInherit() async {
        let seen = await ExportAudience.$current.withValue(.players) {
            await Task.detached { ExportAudience.isPlayerPackage }.value
        }

        #expect(!seen)
    }
}
#endif
