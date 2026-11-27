// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("Foundry LevelDB write-ahead log reader")
struct FoundryLevelDBWriteAheadLogReaderTests {
    @Test("Decodes fragmented WriteBatch puts and deletions")
    func decodesFragmentedWriteBatch() throws {
        // Given
        let largeValue = Data(repeating: 0x61, count: 33_000)
        let batch = WALFixture.writeBatch(sequence: 41, operations: [
            .put("!items!alpha", largeValue),
            .delete("!items!obsolete"),
            .put("!items!omega", Data("new".utf8)),
        ])
        let log = WALFixture.log(logicalRecords: [batch])

        // When
        let records = try FoundryLevelDBWriteAheadLogReader().records(in: log, path: "000007.log")

        // Then
        #expect(records == [
            FoundryLevelDBRecord(
                key: "!items!alpha",
                sequence: 41,
                operation: .value,
                value: largeValue
            ),
            FoundryLevelDBRecord(
                key: "!items!obsolete",
                sequence: 42,
                operation: .deletion,
                value: Data()
            ),
            FoundryLevelDBRecord(
                key: "!items!omega",
                sequence: 43,
                operation: .value,
                value: Data("new".utf8)
            ),
        ])
    }

    @Test("Rejects checksum corruption and incomplete WriteBatch counts")
    func rejectsCorruptRecords() {
        // Given
        let validBatch = WALFixture.writeBatch(sequence: 1, operations: [
            .put("!items!alpha", Data("value".utf8)),
        ])
        var checksumFailure = WALFixture.log(logicalRecords: [validBatch])
        checksumFailure[0] ^= 0xff

        var countFailure = validBatch
        WALFixture.replaceLittleEndian(UInt32(2), at: 8, in: &countFailure)

        // When / Then
        #expect(throws: FoundryImportError.self) {
            try FoundryLevelDBWriteAheadLogReader().records(in: checksumFailure, path: "000001.log")
        }
        #expect(throws: FoundryImportError.self) {
            try FoundryLevelDBWriteAheadLogReader().records(
                in: WALFixture.log(logicalRecords: [countFailure]),
                path: "000001.log"
            )
        }
    }

    @Test("Enforces operation-count and entry-size limits")
    func enforcesLimits() {
        // Given
        let twoOperations = WALFixture.log(logicalRecords: [
            WALFixture.writeBatch(sequence: 1, operations: [
                .delete("a"),
                .delete("b"),
            ]),
        ])
        let oversizedValue = WALFixture.log(logicalRecords: [
            WALFixture.writeBatch(sequence: 1, operations: [
                .put("k", Data(repeating: 0x61, count: 5)),
            ]),
        ])
        let countLimits = FoundryImportLimits(
            maximumArchiveSize: 1_024,
            maximumEntrySize: 1_024,
            maximumRuleDataSize: 1_024,
            maximumDocumentCount: 1
        )
        let sizeLimits = FoundryImportLimits(
            maximumArchiveSize: 1_024,
            maximumEntrySize: 4,
            maximumRuleDataSize: 1_024,
            maximumDocumentCount: 10
        )

        // When / Then
        #expect(throws: FoundryImportError.tooManyDocuments(2)) {
            try FoundryLevelDBWriteAheadLogReader(limits: countLimits).records(in: twoOperations)
        }
        #expect(throws: FoundryImportError.fileTooLarge(5)) {
            try FoundryLevelDBWriteAheadLogReader(limits: sizeLimits).records(in: oversizedValue)
        }
    }

    @Test("Rejects ambiguous reuse of a global sequence number")
    func rejectsAmbiguousSequence() {
        // Given
        let records = [
            FoundryLevelDBRecord(key: "!items!alpha", sequence: 9, operation: .value, value: Data("a".utf8)),
            FoundryLevelDBRecord(key: "!items!beta", sequence: 9, operation: .value, value: Data("b".utf8)),
        ]

        // When / Then
        #expect(throws: FoundryImportError.corruptLevelDB(
            "The same LevelDB sequence number has conflicting records."
        )) {
            try FoundryLevelDBRecordMerger.currentRecords(records)
        }
    }

    @Test("Merges only MANIFEST-live WAL changes with SST records")
    func mergesLiveWALWithSSTable() async throws {
        // Given
        let root = URL.temporaryDirectory.appending(
            path: "FoundryLevelDBWALIntegrationTests-\(UUID())",
            directoryHint: .isDirectory
        )
        let pack = root.appending(path: "packs/items", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(WALFixture.systemManifest.utf8).write(to: root.appending(path: "system.json"))
        let table = FoundryLevelDBFixture.table(records: [
            FoundryLevelDBRecord(
                key: "!items!alpha",
                sequence: 5,
                operation: .value,
                value: Data(#"{"_id":"alpha","name":"Old Alpha","type":"loot"}"#.utf8)
            ),
            FoundryLevelDBRecord(
                key: "!items!beta",
                sequence: 4,
                operation: .value,
                value: Data(#"{"_id":"beta","name":"Old Beta","type":"loot"}"#.utf8)
            ),
        ])
        try table.write(to: pack.appending(path: "000003.ldb"))
        try Data("MANIFEST-000002\n".utf8).write(to: pack.appending(path: "CURRENT"))
        let manifest = WALFixture.log(logicalRecords: [
            WALFixture.manifestEdit(activeTable: 3, logNumber: 6, previousLogNumber: 5, lastSequence: 7),
        ])
        try manifest.write(to: pack.appending(path: "MANIFEST-000002"))

        let staleLog = WALFixture.log(logicalRecords: [
            WALFixture.writeBatch(sequence: 100, operations: [
                .put("!items!stale", Data(#"{"_id":"stale","name":"Must Not Return","type":"loot"}"#.utf8)),
            ]),
        ])
        try staleLog.write(to: pack.appending(path: "000004.log"))
        let previousLiveLog = WALFixture.log(logicalRecords: [
            WALFixture.writeBatch(sequence: 6, operations: [
                .delete("!items!alpha"),
            ]),
        ])
        try previousLiveLog.write(to: pack.appending(path: "000005.log"))
        let currentLiveLog = WALFixture.log(logicalRecords: [
            WALFixture.writeBatch(sequence: 7, operations: [
                .put("!items!beta", Data(#"{"_id":"beta","name":"Live Beta","type":"loot"}"#.utf8)),
            ]),
        ])
        try currentLiveLog.write(to: pack.appending(path: "000006.log"))

        // When
        let package = try await FoundryVTTImportReader().read(from: root)

        // Then
        #expect(package.documents.map(\.documentId) == ["beta"])
        #expect(package.documents.first?.name == "Live Beta")
        #expect(!package.documents.contains { $0.documentId == "stale" })
    }
}

private enum WALFixtureOperation {
    case put(String, Data)
    case delete(String)
}

private enum WALFixture {
    static let systemManifest = #"{"id":"wal-test","title":"WAL Test","version":"1","packs":[{"name":"items","label":"Items","path":"packs/items","type":"Item"}]}"#

    static func writeBatch(sequence: UInt64, operations: [WALFixtureOperation]) -> [UInt8] {
        var result: [UInt8] = []
        appendLittleEndian(sequence, to: &result)
        appendLittleEndian(UInt32(operations.count), to: &result)
        for operation in operations {
            switch operation {
            case .put(let key, let value):
                result.append(FoundryLevelDBRecord.Operation.value.rawValue)
                appendLengthPrefixed(Array(key.utf8), to: &result)
                appendLengthPrefixed(Array(value), to: &result)
            case .delete(let key):
                result.append(FoundryLevelDBRecord.Operation.deletion.rawValue)
                appendLengthPrefixed(Array(key.utf8), to: &result)
            }
        }
        return result
    }

    static func manifestEdit(
        activeTable: UInt64,
        logNumber: UInt64,
        previousLogNumber: UInt64? = nil,
        lastSequence: UInt64
    ) -> [UInt8] {
        var result: [UInt8] = []
        appendVarint(2, to: &result)
        appendVarint(logNumber, to: &result)
        appendVarint(4, to: &result)
        appendVarint(lastSequence, to: &result)
        if let previousLogNumber {
            appendVarint(9, to: &result)
            appendVarint(previousLogNumber, to: &result)
        }
        appendVarint(7, to: &result)
        appendVarint(0, to: &result)
        appendVarint(activeTable, to: &result)
        appendVarint(1, to: &result)
        appendLengthPrefixed([], to: &result)
        appendLengthPrefixed([], to: &result)
        return result
    }

    static func log(logicalRecords: [[UInt8]]) -> Data {
        let blockSize = 32_768
        let headerSize = 7
        var result: [UInt8] = []
        var blockOffset = 0

        for logicalRecord in logicalRecords {
            var recordOffset = 0
            var isFirstFragment = true
            repeat {
                let leftover = blockSize - blockOffset
                if leftover < headerSize {
                    result.append(contentsOf: repeatElement(0, count: leftover))
                    blockOffset = 0
                }
                let available = blockSize - blockOffset - headerSize
                let remaining = logicalRecord.count - recordOffset
                let fragmentLength = min(available, remaining)
                let isLastFragment = fragmentLength == remaining
                let type: UInt8
                if isFirstFragment, isLastFragment {
                    type = 1
                } else if isFirstFragment {
                    type = 2
                } else if isLastFragment {
                    type = 4
                } else {
                    type = 3
                }
                let payload = Array(logicalRecord[recordOffset..<(recordOffset + fragmentLength)])
                appendPhysicalRecord(type: type, payload: payload, to: &result)
                blockOffset += headerSize + fragmentLength
                recordOffset += fragmentLength
                isFirstFragment = false
            } while recordOffset < logicalRecord.count
        }
        return Data(result)
    }

    static func replaceLittleEndian(_ value: UInt32, at offset: Int, in bytes: inout [UInt8]) {
        for index in 0..<4 {
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> UInt32(index * 8))
        }
    }
}

private extension WALFixture {
    static func appendPhysicalRecord(type: UInt8, payload: [UInt8], to bytes: inout [UInt8]) {
        appendLittleEndian(FoundryCRC32C.maskedChecksum([type] + payload), to: &bytes)
        appendLittleEndian(UInt16(payload.count), to: &bytes)
        bytes.append(type)
        bytes.append(contentsOf: payload)
    }

    static func appendLengthPrefixed(_ value: [UInt8], to bytes: inout [UInt8]) {
        appendVarint(UInt64(value.count), to: &bytes)
        bytes.append(contentsOf: value)
    }

    static func appendVarint(_ value: UInt64, to bytes: inout [UInt8]) {
        var remaining = value
        while remaining >= 0x80 {
            bytes.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        bytes.append(UInt8(remaining))
    }

    static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        for index in 0..<MemoryLayout<T>.size {
            bytes.append(UInt8(truncatingIfNeeded: value >> T(index * 8)))
        }
    }
}
