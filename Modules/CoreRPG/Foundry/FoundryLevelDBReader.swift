// @copyright André Trettin

import Foundation

struct FoundryLevelDBRecord: Equatable, Sendable {
    enum Operation: UInt8, Equatable, Sendable {
        case deletion = 0
        case value = 1
    }

    let key: String
    let sequence: UInt64
    let operation: Operation
    let value: Data
}

/// Reads the immutable SSTable files used by Foundry VTT v12 compendium packs.
///
/// Foundry packages may contain several tables. The package loader is responsible for merging
/// records by user key and LevelDB sequence number after each table has been decoded.
struct FoundryLevelDBTableReader: Sendable {
    private static let tableMagicNumber: UInt64 = 0xdb47_7524_8b80_fb57
    private static let footerSize = 48
    private static let blockTrailerSize = 5

    let limits: FoundryImportLimits

    init(limits: FoundryImportLimits = .default) {
        self.limits = limits
    }

    func records(in data: Data) throws -> [FoundryLevelDBRecord] {
        try Task.checkCancellation()
        guard data.count >= Self.footerSize else {
            throw FoundryImportError.corruptLevelDB("The table footer is missing.")
        }
        guard data.count <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(data.count)
        }

        let bytes = [UInt8](data)
        let footerOffset = bytes.count - Self.footerSize
        let magic = try bytes.littleEndianUInt64(at: bytes.count - MemoryLayout<UInt64>.size)
        guard magic == Self.tableMagicNumber else {
            throw FoundryImportError.corruptLevelDB("The table magic number is invalid.")
        }

        var footerCursor = footerOffset
        _ = try decodeBlockHandle(bytes, cursor: &footerCursor, limit: footerOffset + 40)
        let indexHandle = try decodeBlockHandle(bytes, cursor: &footerCursor, limit: footerOffset + 40)
        let indexBlock = try readBlock(handle: indexHandle, bytes: bytes, tableDataLimit: footerOffset)
        let indexEntries = try decodeEntries(in: indexBlock)
        var totalDecodedBlockBytes = indexBlock.count
        guard totalDecodedBlockBytes <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(totalDecodedBlockBytes)
        }

        var records: [FoundryLevelDBRecord] = []
        for indexEntry in indexEntries {
            try Task.checkCancellation()
            var handleCursor = 0
            let dataHandle = try decodeBlockHandle(indexEntry.value, cursor: &handleCursor, limit: indexEntry.value.count)
            guard handleCursor == indexEntry.value.count else {
                throw FoundryImportError.corruptLevelDB("An index entry contains an invalid block handle.")
            }
            let block = try readBlock(handle: dataHandle, bytes: bytes, tableDataLimit: footerOffset)
            let (nextDecodedBlockBytes, overflow) = totalDecodedBlockBytes.addingReportingOverflow(block.count)
            guard !overflow, nextDecodedBlockBytes <= limits.maximumRuleDataSize else {
                throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextDecodedBlockBytes)
            }
            totalDecodedBlockBytes = nextDecodedBlockBytes
            for entry in try decodeEntries(in: block) {
                let record = try decodeRecord(entry)
                records.append(record)
                guard records.count <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(records.count)
                }
            }
        }
        return records
    }
}

private extension FoundryLevelDBTableReader {
    struct BlockHandle: Sendable {
        let offset: Int
        let size: Int
    }

    struct BlockEntry: Sendable {
        let key: [UInt8]
        let value: [UInt8]
    }

    func decodeBlockHandle(_ bytes: [UInt8], cursor: inout Int, limit: Int) throws -> BlockHandle {
        let offset = try bytes.readVarint64(cursor: &cursor, limit: limit)
        let size = try bytes.readVarint64(cursor: &cursor, limit: limit)
        guard offset <= UInt64(Int.max), size <= UInt64(Int.max) else {
            throw FoundryImportError.corruptLevelDB("A block handle is too large.")
        }
        return BlockHandle(offset: Int(offset), size: Int(size))
    }

    func readBlock(handle: BlockHandle, bytes: [UInt8], tableDataLimit: Int) throws -> [UInt8] {
        guard handle.offset >= 0, handle.size >= 0,
              tableDataLimit >= 0, tableDataLimit <= bytes.count,
              handle.offset <= tableDataLimit,
              handle.size <= tableDataLimit - handle.offset,
              Self.blockTrailerSize <= tableDataLimit - handle.offset - handle.size else {
            throw FoundryImportError.corruptLevelDB("A block points outside its table.")
        }
        guard handle.size <= limits.maximumEntrySize else {
            throw FoundryImportError.fileTooLarge(handle.size)
        }

        let contentRange = handle.offset..<(handle.offset + handle.size)
        let compression = bytes[contentRange.upperBound]
        let storedChecksum = try bytes.littleEndianUInt32(at: contentRange.upperBound + 1)
        let checksumInput = Array(bytes[contentRange]) + [compression]
        guard FoundryCRC32C.maskedChecksum(checksumInput) == storedChecksum else {
            throw FoundryImportError.corruptLevelDB("A block checksum does not match.")
        }

        switch compression {
        case 0:
            return Array(bytes[contentRange])
        case 1:
            return try FoundrySnappyDecoder(maximumOutputSize: limits.maximumEntrySize)
                .decode(Array(bytes[contentRange]))
        default:
            throw FoundryImportError.unsupportedLevelDBCompression(compression)
        }
    }

    /// Foundry document keys are short ids; anything beyond this is treated as corrupt.
    static let maximumKeyLength = 4_096

    func decodeEntries(in block: [UInt8]) throws -> [BlockEntry] {
        guard block.count >= MemoryLayout<UInt32>.size else {
            throw FoundryImportError.corruptLevelDB("A data block has no restart table.")
        }
        let restartCount = try block.littleEndianUInt32(at: block.count - 4)
        guard restartCount > 0 else {
            throw FoundryImportError.corruptLevelDB("A data block restart count is invalid.")
        }
        let restartByteCount = Int(restartCount) * 4
        guard restartByteCount <= block.count - 4 else {
            throw FoundryImportError.corruptLevelDB("A data block restart table is truncated.")
        }
        let restartOffset = block.count - 4 - restartByteCount
        guard restartOffset <= UInt32.max else {
            throw FoundryImportError.corruptLevelDB("A data block is too large for its restart table.")
        }
        guard try block.littleEndianUInt32(at: restartOffset) == 0 else {
            throw FoundryImportError.corruptLevelDB("A data block does not start at restart zero.")
        }

        var previousRestart: UInt32 = 0
        var restartOffsets: [Int] = []
        restartOffsets.reserveCapacity(Int(restartCount))
        for index in 0..<Int(restartCount) {
            let restart = try block.littleEndianUInt32(at: restartOffset + index * 4)
            let isInEntryData = restartOffset == 0 ? restart == 0 : restart < UInt32(restartOffset)
            let isOrdered = index == 0 ? restart == 0 : restart > previousRestart
            guard isInEntryData, isOrdered else {
                throw FoundryImportError.corruptLevelDB("A data block restart offset is invalid.")
            }
            previousRestart = restart
            restartOffsets.append(Int(restart))
        }

        if restartOffset == 0 {
            guard restartOffsets == [0] else {
                throw FoundryImportError.corruptLevelDB("An empty data block has an invalid restart table.")
            }
            return []
        }

        var cursor = 0
        var previousKey: [UInt8] = []
        var entries: [BlockEntry] = []
        let restartOffsetSet = Set(restartOffsets)
        var decodedEntryOffsets = Set<Int>()
        // Prefix sharing lets a few bytes per entry reconstruct a full-length key, so bound the
        // key length and the cumulative reconstructed bytes. See CODE_AUDIT_16 §6.1.
        var decodedBytes = 0
        while cursor < restartOffset {
            let entryOffset = cursor
            let sharedLength = try block.readVarint32(cursor: &cursor, limit: restartOffset)
            let unsharedLength = try block.readVarint32(cursor: &cursor, limit: restartOffset)
            let valueLength = try block.readVarint32(cursor: &cursor, limit: restartOffset)
            guard !restartOffsetSet.contains(entryOffset) || sharedLength == 0 else {
                throw FoundryImportError.corruptLevelDB("A data block restart entry has a shared key prefix.")
            }
            guard UInt64(sharedLength) <= UInt64(previousKey.count) else {
                throw FoundryImportError.corruptLevelDB("A block entry length is invalid.")
            }

            let unsharedCount = Int(unsharedLength)
            let valueCount = Int(valueLength)
            guard unsharedCount <= restartOffset - cursor else {
                throw FoundryImportError.corruptLevelDB("A block key is truncated.")
            }
            let keyEnd = cursor + unsharedCount
            guard valueCount <= restartOffset - keyEnd else {
                throw FoundryImportError.corruptLevelDB("A block value is truncated.")
            }

            let keyLength = Int(sharedLength) + unsharedCount
            guard keyLength <= Self.maximumKeyLength else {
                throw FoundryImportError.corruptLevelDB("A block key is too long.")
            }
            decodedBytes += keyLength + valueCount
            guard decodedBytes <= limits.maximumRuleDataSize else {
                throw FoundryImportError.corruptLevelDB("A data block expands beyond the import limit.")
            }

            var key = Array(previousKey.prefix(Int(sharedLength)))
            key.append(contentsOf: block[cursor..<keyEnd])
            let valueEnd = keyEnd + valueCount
            entries.append(BlockEntry(key: key, value: Array(block[keyEnd..<valueEnd])))
            guard entries.count <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(entries.count)
            }
            decodedEntryOffsets.insert(entryOffset)
            previousKey = key
            cursor = valueEnd
        }
        guard cursor == restartOffset else {
            throw FoundryImportError.corruptLevelDB("A data block ended between entries.")
        }
        guard restartOffsets.allSatisfy(decodedEntryOffsets.contains) else {
            throw FoundryImportError.corruptLevelDB("A data block restart does not point to an entry.")
        }
        return entries
    }

    func decodeRecord(_ entry: BlockEntry) throws -> FoundryLevelDBRecord {
        guard entry.key.count >= MemoryLayout<UInt64>.size else {
            throw FoundryImportError.corruptLevelDB("An internal key has no sequence trailer.")
        }
        let trailerOffset = entry.key.count - MemoryLayout<UInt64>.size
        let trailer = try entry.key.littleEndianUInt64(at: trailerOffset)
        guard let operation = FoundryLevelDBRecord.Operation(rawValue: UInt8(trailer & 0xff)) else {
            throw FoundryImportError.corruptLevelDB("An internal key has an unknown value type.")
        }
        guard let key = String(bytes: entry.key[..<trailerOffset], encoding: .utf8) else {
            throw FoundryImportError.corruptLevelDB("A user key is not UTF-8.")
        }
        return FoundryLevelDBRecord(
            key: key,
            sequence: trailer >> 8,
            operation: operation,
            value: Data(entry.value)
        )
    }
}

struct FoundrySnappyDecoder: Sendable {
    let maximumOutputSize: Int

    func decode(_ input: [UInt8]) throws -> [UInt8] {
        var cursor = 0
        let expectedLength = try input.readVarint32(cursor: &cursor, limit: input.count)
        guard Int(expectedLength) <= maximumOutputSize else {
            throw FoundryImportError.fileTooLarge(Int(expectedLength))
        }

        var output: [UInt8] = []
        output.reserveCapacity(Int(expectedLength))
        while cursor < input.count {
            let tag = input[cursor]
            cursor += 1
            switch tag & 0x03 {
            case 0:
                let encodedLength = Int(tag >> 2)
                let literalLength: Int
                if encodedLength < 60 {
                    literalLength = encodedLength + 1
                } else {
                    let byteCount = encodedLength - 59
                    guard byteCount <= 4, byteCount <= input.count - cursor else {
                        throw FoundryImportError.corruptLevelDB("A Snappy literal length is truncated.")
                    }
                    var lengthMinusOne: UInt32 = 0
                    for byteIndex in 0..<byteCount {
                        lengthMinusOne |= UInt32(input[cursor + byteIndex]) << UInt32(byteIndex * 8)
                    }
                    cursor += byteCount
                    guard lengthMinusOne < UInt32.max else {
                        throw FoundryImportError.corruptLevelDB("A Snappy literal is too large.")
                    }
                    literalLength = Int(lengthMinusOne) + 1
                }
                guard literalLength <= input.count - cursor,
                      literalLength <= Int(expectedLength) - output.count else {
                    throw FoundryImportError.corruptLevelDB("A Snappy literal exceeds its block.")
                }
                output.append(contentsOf: input[cursor..<(cursor + literalLength)])
                cursor += literalLength
            case 1:
                guard cursor < input.count else {
                    throw FoundryImportError.corruptLevelDB("A Snappy copy offset is truncated.")
                }
                let length = 4 + Int((tag >> 2) & 0x07)
                let offset = (Int(tag & 0xe0) << 3) | Int(input[cursor])
                cursor += 1
                try appendCopy(length: length, offset: offset, expectedLength: Int(expectedLength), to: &output)
            case 2:
                guard 2 <= input.count - cursor else {
                    throw FoundryImportError.corruptLevelDB("A Snappy copy offset is truncated.")
                }
                let length = 1 + Int(tag >> 2)
                let offset = Int(input[cursor]) | (Int(input[cursor + 1]) << 8)
                cursor += 2
                try appendCopy(length: length, offset: offset, expectedLength: Int(expectedLength), to: &output)
            case 3:
                guard 4 <= input.count - cursor else {
                    throw FoundryImportError.corruptLevelDB("A Snappy copy offset is truncated.")
                }
                let length = 1 + Int(tag >> 2)
                let offsetValue = UInt32(input[cursor])
                    | (UInt32(input[cursor + 1]) << 8)
                    | (UInt32(input[cursor + 2]) << 16)
                    | (UInt32(input[cursor + 3]) << 24)
                cursor += 4
                try appendCopy(length: length, offset: Int(offsetValue), expectedLength: Int(expectedLength), to: &output)
            default:
                throw FoundryImportError.corruptLevelDB("A Snappy tag is invalid.")
            }
        }
        guard output.count == Int(expectedLength) else {
            throw FoundryImportError.corruptLevelDB("A Snappy block has the wrong decoded size.")
        }
        return output
    }
}

private extension FoundrySnappyDecoder {
    func appendCopy(length: Int, offset: Int, expectedLength: Int, to output: inout [UInt8]) throws {
        guard offset > 0, offset <= output.count,
              length <= expectedLength - output.count else {
            throw FoundryImportError.corruptLevelDB("A Snappy copy points outside its decoded data.")
        }
        let start = output.count - offset
        if offset >= length {
            // Source and target do not overlap: one slice append (the slice is copied first, so the
            // append does not copy the whole output). See CODE_AUDIT_26 §7.34.
            let chunk = Array(output[start..<start + length])
            output.append(contentsOf: chunk)
        } else {
            // An overlapping copy repeats the last `offset` bytes, so it is read as it is written.
            for index in 0..<length {
                output.append(output[start + index])
            }
        }
    }
}

enum FoundryCRC32C {
    private static let reversedPolynomial: UInt32 = 0x82f6_3b78
    private static let maskDelta: UInt32 = 0xa282_ead8

    static func maskedChecksum(_ bytes: [UInt8]) -> UInt32 {
        let checksum = checksum(bytes)
        return ((checksum >> 15) | (checksum << 17)) &+ maskDelta
    }

    /// The byte-at-a-time lookup table of the reflected CRC-32C polynomial.
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var crc = UInt32(index)
        for _ in 0..<8 {
            let mask = UInt32(bitPattern: -Int32(crc & 1))
            crc = (crc >> 1) ^ (reversedPolynomial & mask)
        }
        return crc
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        checksum(bytes[...])
    }

    /// Table driven (one lookup per byte instead of eight shift/XOR steps); a slice is
    /// checksummed without copying it. See CODE_AUDIT_26 §7.34.
    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc = UInt32.max
        table.withUnsafeBufferPointer { table in
            for byte in bytes {
                crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xff)]
            }
        }
        return ~crc
    }
}

extension Array where Element == UInt8 {
    func littleEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, 4 <= count - offset else {
            throw FoundryImportError.corruptLevelDB("A 32-bit value is truncated.")
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func littleEndianUInt64(at offset: Int) throws -> UInt64 {
        guard offset >= 0, 8 <= count - offset else {
            throw FoundryImportError.corruptLevelDB("A 64-bit value is truncated.")
        }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(self[offset + index]) << UInt64(index * 8)
        }
        return value
    }

    func readVarint32(cursor: inout Int, limit: Int) throws -> UInt32 {
        let value = try readVarint64(cursor: &cursor, limit: limit, maximumByteCount: 5)
        guard value <= UInt32.max else {
            throw FoundryImportError.corruptLevelDB("A 32-bit varint is too large.")
        }
        return UInt32(value)
    }

    func readVarint64(cursor: inout Int, limit: Int, maximumByteCount: Int = 10) throws -> UInt64 {
        guard cursor >= 0, limit <= count, cursor <= limit else {
            throw FoundryImportError.corruptLevelDB("A varint has invalid bounds.")
        }
        var value: UInt64 = 0
        for byteIndex in 0..<maximumByteCount {
            guard cursor < limit else {
                throw FoundryImportError.corruptLevelDB("A varint is truncated.")
            }
            let byte = self[cursor]
            cursor += 1
            if byteIndex == 9, byte > 1 {
                throw FoundryImportError.corruptLevelDB("A varint overflows 64 bits.")
            }
            value |= UInt64(byte & 0x7f) << UInt64(byteIndex * 7)
            if byte & 0x80 == 0 {
                return value
            }
        }
        throw FoundryImportError.corruptLevelDB("A varint is too long.")
    }
}
