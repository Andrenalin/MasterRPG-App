// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("Foundry ZIP archive")
struct FoundryZIPArchiveTests {
    @Test("Reads stored entries and finds matching paths")
    func readsStoredEntries() throws {
        // Given
        let manifest = Data("{\"id\":\"ds4\"}".utf8)
        let archiveData = makeZIP(entries: [
            .stored(path: "ds4/system.json", data: manifest),
            .stored(path: "ds4/packs/items/LOCK", data: Data())
        ])

        // When
        let archive = try FoundryZIPArchive(data: archiveData)
        let jsonPaths = archive.paths { $0.hasSuffix(".json") }

        // Then
        #expect(archive.entryPaths == ["ds4/system.json", "ds4/packs/items/LOCK"])
        #expect(archive.contains(path: "ds4/system.json"))
        #expect(jsonPaths == ["ds4/system.json"])
        #expect(try archive.data(forPath: "ds4/system.json") == manifest)
        #expect(try archive.data(forPath: "missing.json") == nil)
    }

    @Test("Inflates raw Deflate entries")
    func inflatesRawDeflate() throws {
        // Given
        let uncompressed = Data("Foundry rules".utf8)
        let rawDeflate = Data([0x73, 0xCB, 0x2F, 0xCD, 0x4B, 0x29, 0xAA, 0x54, 0x28, 0x2A, 0xCD, 0x49, 0x2D, 0x06, 0x00])
        let archiveData = makeZIP(entries: [
            .deflated(path: "ds4/template.json", compressedData: rawDeflate, uncompressedData: uncompressed)
        ])

        // When
        let archive = try FoundryZIPArchive(data: archiveData)

        // Then
        #expect(try archive.data(forPath: "ds4/template.json") == uncompressed)
    }

    @Test("Rejects unsafe traversal paths")
    func rejectsTraversalPath() {
        let archiveData = makeZIP(entries: [
            .stored(path: "../system.json", data: Data("{}".utf8))
        ])

        #expect(throws: FoundryImportError.self) {
            _ = try FoundryZIPArchive(data: archiveData)
        }
    }

    @Test("Rejects encrypted entries")
    func rejectsEncryption() {
        let archiveData = makeZIP(entries: [
            .stored(path: "ds4/system.json", data: Data("{}".utf8), flags: 0x0001)
        ])

        #expect(throws: FoundryImportError.encryptedArchive) {
            _ = try FoundryZIPArchive(data: archiveData)
        }
    }

    @Test("Enforces the per-entry expanded size limit")
    func enforcesEntrySizeLimit() {
        let archiveData = makeZIP(entries: [
            .stored(path: "ds4/system.json", data: Data("large".utf8))
        ])
        let limits = FoundryImportLimits(maximumEntrySize: 4)

        #expect(throws: FoundryImportError.fileTooLarge(5)) {
            _ = try FoundryZIPArchive(data: archiveData, limits: limits)
        }
    }

    @Test("An archive whose artwork exceeds the rule-data budget still opens (CODE_AUDIT §5.19)")
    func totalSizeFollowsTheArchiveLimitNotTheRuleDataBudget() throws {
        let archiveData = makeZIP(entries: [
            .stored(path: "ds4/system.json", data: Data("{}".utf8)),
            .stored(path: "ds4/art/map.webp", data: Data(repeating: 0x61, count: 64))
        ])
        let limits = FoundryImportLimits(maximumRuleDataSize: 16)

        let archive = try FoundryZIPArchive(data: archiveData, limits: limits)

        #expect(try archive.data(forPath: "ds4/system.json") == Data("{}".utf8))
    }

    @Test("Checks CRC-32 before returning entry data")
    func verifiesChecksum() throws {
        let archiveData = makeZIP(entries: [
            .stored(path: "ds4/system.json", data: Data("{}".utf8), checksumOverride: 0)
        ])
        let archive = try FoundryZIPArchive(data: archiveData)

        #expect(throws: FoundryImportError.self) {
            _ = try archive.data(forPath: "ds4/system.json")
        }
    }
}

private struct ZIPFixtureEntry {
    let path: String
    let flags: UInt16
    let method: UInt16
    let compressedData: Data
    let uncompressedData: Data
    let checksum: UInt32

    static func stored(
        path: String,
        data: Data,
        flags: UInt16 = 0x0800,
        checksumOverride: UInt32? = nil
    ) -> Self {
        Self(
            path: path,
            flags: flags,
            method: 0,
            compressedData: data,
            uncompressedData: data,
            checksum: checksumOverride ?? crc32(of: data)
        )
    }

    static func deflated(path: String, compressedData: Data, uncompressedData: Data) -> Self {
        Self(
            path: path,
            flags: 0x0800,
            method: 8,
            compressedData: compressedData,
            uncompressedData: uncompressedData,
            checksum: crc32(of: uncompressedData)
        )
    }
}

private func makeZIP(entries: [ZIPFixtureEntry]) -> Data {
    var localRecords = Data()
    var centralDirectory = Data()

    for entry in entries {
        let pathData = Data(entry.path.utf8)
        let localOffset = UInt32(localRecords.count)

        localRecords.appendLittleEndian(UInt32(0x0403_4B50))
        localRecords.appendLittleEndian(UInt16(20))
        localRecords.appendLittleEndian(entry.flags)
        localRecords.appendLittleEndian(entry.method)
        localRecords.appendLittleEndian(UInt16(0))
        localRecords.appendLittleEndian(UInt16(0))
        localRecords.appendLittleEndian(entry.checksum)
        localRecords.appendLittleEndian(UInt32(entry.compressedData.count))
        localRecords.appendLittleEndian(UInt32(entry.uncompressedData.count))
        localRecords.appendLittleEndian(UInt16(pathData.count))
        localRecords.appendLittleEndian(UInt16(0))
        localRecords.append(pathData)
        localRecords.append(entry.compressedData)

        centralDirectory.appendLittleEndian(UInt32(0x0201_4B50))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(UInt16(20))
        centralDirectory.appendLittleEndian(entry.flags)
        centralDirectory.appendLittleEndian(entry.method)
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(entry.checksum)
        centralDirectory.appendLittleEndian(UInt32(entry.compressedData.count))
        centralDirectory.appendLittleEndian(UInt32(entry.uncompressedData.count))
        centralDirectory.appendLittleEndian(UInt16(pathData.count))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt16(0))
        centralDirectory.appendLittleEndian(UInt32(0))
        centralDirectory.appendLittleEndian(localOffset)
        centralDirectory.append(pathData)
    }

    var archive = localRecords
    let centralDirectoryOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    archive.appendLittleEndian(UInt32(0x0605_4B50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt32(centralDirectory.count))
    archive.appendLittleEndian(centralDirectoryOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
}

private func crc32(of data: Data) -> UInt32 {
    var checksum = UInt32.max
    for byte in data {
        checksum ^= UInt32(byte)
        for _ in 0..<8 {
            let mask = UInt32(bitPattern: -Int32(checksum & 1))
            checksum = checksum >> 1 ^ (0xEDB8_8320 & mask)
        }
    }
    return checksum ^ UInt32.max
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
