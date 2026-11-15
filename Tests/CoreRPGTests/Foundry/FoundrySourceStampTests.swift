// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §3.3: a mapped source file that changes during the import is noticed.
struct FoundrySourceStampTests {
    @Test func aChangedSourceFileIsNoLongerUnchanged() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
        try Data(repeating: 1, count: 64).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let stamp = FoundryZIPArchive.SourceStamp(url: url)
        #expect(stamp.isUnchanged)

        try Data(repeating: 2, count: 128).write(to: url)
        #expect(!stamp.isUnchanged)
    }

    @Test func aMissingSourceFileIsNotUnchanged() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
        try Data(repeating: 1, count: 8).write(to: url)
        let stamp = FoundryZIPArchive.SourceStamp(url: url)
        try FileManager.default.removeItem(at: url)
        #expect(!stamp.isUnchanged)
    }
}
#endif
