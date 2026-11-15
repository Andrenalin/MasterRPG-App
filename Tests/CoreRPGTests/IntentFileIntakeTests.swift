// @copyright André Trettin

import AppIntents
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// CODE_AUDIT_AppIntents2 §4.4: the optional file of a Create intent is checked against the module's
/// types before an item exists, so a wrong file leaves nothing behind.
@Suite("Intent file intake")
struct IntentFileIntakeTests {
    private let bytes = Data([1, 2, 3])

    @Test("No file passed returns no data")
    func noFile() async throws {
        #expect(try await intentFileData(nil, allowedTypes: [.pdf]) == nil)
    }

    @Test("A file of an allowed type returns its bytes")
    func allowedType() async throws {
        let file = IntentFile(data: bytes, filename: "rules.pdf", type: .pdf)
        #expect(try await intentFileData(file, allowedTypes: [.pdf]) == bytes)
    }

    @Test("A subtype conforms to the allowed type")
    func conformingType() async throws {
        let file = IntentFile(data: bytes, filename: "tavern.mp3", type: .mp3)
        #expect(try await intentFileData(file, allowedTypes: [.audio]) == bytes)
    }

    @Test("The file name's extension stands in when the type is missing")
    func typeFromExtension() async throws {
        let file = IntentFile(data: bytes, filename: "dragon.usdz")
        #expect(try await intentFileData(file, allowedTypes: [.usdz]) == bytes)
    }

    @Test("A file of another type is rejected", arguments: [UTType.png, .plainText, .movie])
    func wrongType(type: UTType) async {
        let file = IntentFile(data: bytes, filename: "file", type: type)
        await #expect(throws: IntentFileTypeError.self) {
            try await intentFileData(file, allowedTypes: [.pdf])
        }
    }

    @Test("A file with no known type and no extension is rejected")
    func unknownType() async {
        let file = IntentFile(data: bytes, filename: "file")
        await #expect(throws: IntentFileTypeError.self) {
            try await intentFileData(file, allowedTypes: [.pdf])
        }
    }

    // CODE_AUDIT_26 §6.10
    @Test("A file above the size limit is rejected, one at the limit is read")
    func sizeLimit() async throws {
        let file = IntentFile(data: bytes, filename: "rules.pdf", type: .pdf)
        #expect(try await intentFileData(file, allowedTypes: [.pdf], maximumBytes: 3) == bytes)
        await #expect(throws: IntentFileSizeError.self) {
            try await intentFileData(file, allowedTypes: [.pdf], maximumBytes: 2)
        }
    }

    @Test("A file on disk is measured before it is read")
    func sizeLimitOnDisk() async throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes.write(to: url)
        let file = IntentFile(fileURL: url, filename: "rules.pdf", type: .pdf)

        await #expect(throws: IntentFileSizeError.self) {
            try await intentFileData(file, allowedTypes: [.pdf], maximumBytes: 2)
        }
        #expect(try await intentFileData(file, allowedTypes: [.pdf], maximumBytes: 3) == bytes)
    }

    @Test("A module that holds no file takes none")
    func moduleWithoutFiles() async {
        let file = IntentFile(data: bytes, filename: "rules.pdf", type: .pdf)
        await #expect(throws: IntentFileTypeError.self) {
            try await intentFileData(file, allowedTypes: [])
        }
    }
}
