// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import SpaceRPG

/// CODE_AUDIT_28 §5.20: the viewer was keyed on the item id alone, so a replaced file never reloaded
/// and a failed load stayed failed.
@Suite("Space viewer load key")
struct SpaceViewerLoadKeyTests {
    private let id = UUID()

    @Test("A new file version is a new load")
    func versionChangesKey() {
        #expect(SpaceViewerLoadKey(id: id, version: 1) != SpaceViewerLoadKey(id: id, version: 2))
    }

    @Test("A retry is a new load")
    func retryChangesKey() {
        #expect(SpaceViewerLoadKey(id: id, version: 1) != SpaceViewerLoadKey(id: id, version: 1, attempt: 1))
    }

    @Test("The same item, version and attempt keep the viewer")
    func sameKeyIsStable() {
        #expect(SpaceViewerLoadKey(id: id, version: 3, attempt: 2) == SpaceViewerLoadKey(id: id, version: 3, attempt: 2))
    }
}
#endif
