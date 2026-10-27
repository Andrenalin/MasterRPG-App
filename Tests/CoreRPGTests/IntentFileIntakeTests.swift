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
    func noFile() throws {
        #expect(try intentFileData(nil, allowedTypes: [.pdf]) == nil)
    }

    @Test("A file of an allowed type returns its bytes")
    func allowedType() throws {
        let file = IntentFile(data: bytes, filename: "rules.pdf", type: .pdf)
        #expect(try intentFileData(file, allowedTypes: [.pdf]) == bytes)
    }

    @Test("A subtype conforms to the allowed type")
    func conformingType() throws {
        let file = IntentFile(data: bytes, filename: "tavern.mp3", type: .mp3)
        #expect(try intentFileData(file, allowedTypes: [.audio]) == bytes)
    }

    @Test("The file name's extension stands in when the type is missing")
    func typeFromExtension() throws {
        let file = IntentFile(data: bytes, filename: "dragon.usdz")
        #expect(try intentFileData(file, allowedTypes: [.usdz]) == bytes)
    }

    @Test("A file of another type is rejected", arguments: [UTType.png, .plainText, .movie])
    func wrongType(type: UTType) {
        let file = IntentFile(data: bytes, filename: "file", type: type)
        #expect(throws: IntentFileTypeError.self) {
            try intentFileData(file, allowedTypes: [.pdf])
        }
    }

    @Test("A file with no known type and no extension is rejected")
    func unknownType() {
        let file = IntentFile(data: bytes, filename: "file")
        #expect(throws: IntentFileTypeError.self) {
            try intentFileData(file, allowedTypes: [.pdf])
        }
    }

    @Test("A module that holds no file takes none")
    func moduleWithoutFiles() {
        let file = IntentFile(data: bytes, filename: "rules.pdf", type: .pdf)
        #expect(throws: IntentFileTypeError.self) {
            try intentFileData(file, allowedTypes: [])
        }
    }
}
