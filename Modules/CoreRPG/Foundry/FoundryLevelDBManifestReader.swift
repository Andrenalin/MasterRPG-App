// @copyright André Trettin

import Foundation

struct FoundryLevelDBManifestState: Equatable, Sendable {
    var activeFileNumbers: Set<UInt64> = []
    var logNumber: UInt64?
    var previousLogNumber: UInt64?
    var lastSequence: UInt64?
}

/// Reads the live SSTable and write-ahead-log state recorded by a LevelDB MANIFEST.
///
/// This deliberately decodes only VersionEdit metadata. It does not interpret document values.
struct FoundryLevelDBManifestReader: Sendable {
    let limits: FoundryImportLimits

    init(limits: FoundryImportLimits = .default) {
        self.limits = limits
    }

    func activeFileNumbers(in data: Data) throws -> Set<UInt64> {
        try state(in: data).activeFileNumbers
    }

    func state(in data: Data) throws -> FoundryLevelDBManifestState {
        var state = FoundryLevelDBManifestState()
        let edits = try FoundryLevelDBPhysicalLogReader(
            limits: limits,
            context: "LevelDB MANIFEST"
        ).logicalRecords(in: data)
        for edit in edits {
            try applyVersionEdit(edit, to: &state)
        }
        return state
    }
}

private extension FoundryLevelDBManifestReader {
    func applyVersionEdit(_ bytes: [UInt8], to state: inout FoundryLevelDBManifestState) throws {
        var cursor = 0
        while cursor < bytes.count {
            let tag = try bytes.readVarint32(cursor: &cursor, limit: bytes.count)
            switch tag {
            case 1: // comparator
                _ = try readSlice(bytes, cursor: &cursor)
            case 2: // log number
                state.logNumber = try bytes.readVarint64(cursor: &cursor, limit: bytes.count)
            case 3: // next file number
                _ = try bytes.readVarint64(cursor: &cursor, limit: bytes.count)
            case 4: // last sequence
                state.lastSequence = try bytes.readVarint64(cursor: &cursor, limit: bytes.count)
            case 5: // compact pointer: level + internal key
                _ = try bytes.readVarint32(cursor: &cursor, limit: bytes.count)
                _ = try readSlice(bytes, cursor: &cursor)
            case 6: // deleted file: level + file number
                _ = try bytes.readVarint32(cursor: &cursor, limit: bytes.count)
                state.activeFileNumbers.remove(try bytes.readVarint64(cursor: &cursor, limit: bytes.count))
            case 7: // new file: level, file number, size, smallest key, largest key
                _ = try bytes.readVarint32(cursor: &cursor, limit: bytes.count)
                let fileNumber = try bytes.readVarint64(cursor: &cursor, limit: bytes.count)
                _ = try bytes.readVarint64(cursor: &cursor, limit: bytes.count)
                _ = try readSlice(bytes, cursor: &cursor)
                _ = try readSlice(bytes, cursor: &cursor)
                state.activeFileNumbers.insert(fileNumber)
            case 9: // previous log number
                state.previousLogNumber = try bytes.readVarint64(cursor: &cursor, limit: bytes.count)
            default:
                throw FoundryImportError.corruptLevelDB("The MANIFEST contains unsupported VersionEdit tag \(tag).")
            }
        }
    }

    func readSlice(_ bytes: [UInt8], cursor: inout Int) throws -> ArraySlice<UInt8> {
        let length = try bytes.readVarint32(cursor: &cursor, limit: bytes.count)
        guard Int(length) <= bytes.count - cursor else {
            throw FoundryImportError.corruptLevelDB("A MANIFEST VersionEdit slice is truncated.")
        }
        let end = cursor + Int(length)
        defer { cursor = end }
        return bytes[cursor..<end]
    }
}
