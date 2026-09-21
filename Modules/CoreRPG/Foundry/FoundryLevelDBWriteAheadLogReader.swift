// @copyright André Trettin

import Foundation

/// Decodes the physical-record envelope shared by LevelDB MANIFEST and write-ahead logs.
struct FoundryLevelDBPhysicalLogReader: Sendable {
    private static let blockSize = 32_768
    private static let headerSize = 7

    let limits: FoundryImportLimits
    let context: String

    init(limits: FoundryImportLimits = .default, context: String) {
        self.limits = limits
        self.context = context
    }

    func logicalRecords(in data: Data) throws -> [[UInt8]] {
        guard data.count <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(data.count)
        }

        let bytes = [UInt8](data)
        var cursor = 0
        var fragmented: [UInt8]?
        var result: [[UInt8]] = []
        var decodedByteCount = 0

        while cursor < bytes.count {
            try Task.checkCancellation()
            let blockOffset = cursor % Self.blockSize
            let remainingInBlock = Self.blockSize - blockOffset
            if remainingInBlock < Self.headerSize {
                let trailerCount = min(remainingInBlock, bytes.count - cursor)
                guard bytes[cursor..<(cursor + trailerCount)].allSatisfy({ $0 == 0 }) else {
                    throw corrupt("has non-zero bytes in a block trailer")
                }
                cursor += trailerCount
                continue
            }

            guard Self.headerSize <= bytes.count - cursor else {
                guard bytes[cursor...].allSatisfy({ $0 == 0 }) else {
                    throw corrupt("has a truncated physical-record header")
                }
                break
            }

            let checksum = try bytes.littleEndianUInt32(at: cursor)
            let length = Int(bytes[cursor + 4]) | (Int(bytes[cursor + 5]) << 8)
            let rawType = bytes[cursor + 6]
            if checksum == 0, length == 0, rawType == 0 {
                guard fragmented == nil else {
                    throw corrupt("contains zero padding inside a fragmented record")
                }
                let paddingCount = min(remainingInBlock, bytes.count - cursor)
                guard bytes[cursor..<(cursor + paddingCount)].allSatisfy({ $0 == 0 }) else {
                    throw corrupt("contains an invalid zero physical record")
                }
                cursor += paddingCount
                continue
            }

            guard let type = RecordType(rawValue: rawType),
                  length <= remainingInBlock - Self.headerSize,
                  length <= bytes.count - cursor - Self.headerSize else {
                throw corrupt("contains an invalid physical record")
            }

            let payloadStart = cursor + Self.headerSize
            let payloadEnd = payloadStart + length
            let payload = Array(bytes[payloadStart..<payloadEnd])
            guard FoundryCRC32C.maskedChecksum([rawType] + payload) == checksum else {
                throw corrupt("contains a physical-record checksum mismatch")
            }
            cursor = payloadEnd

            switch type {
            case .full:
                guard fragmented == nil else {
                    throw corrupt("contains an incomplete fragmented record")
                }
                try append(payload, to: &result, decodedByteCount: &decodedByteCount)
            case .first:
                guard fragmented == nil else {
                    throw corrupt("contains overlapping fragmented records")
                }
                fragmented = payload
            case .middle:
                guard var value = fragmented else {
                    throw corrupt("contains a middle fragment without a first fragment")
                }
                // Take the buffer out of `fragmented` first: while both hold it, `append`
                // copies the whole accumulated record per fragment. See CODE_AUDIT_16 §7.1.
                fragmented = nil
                try appendFragment(payload, to: &value)
                fragmented = value
            case .last:
                guard var value = fragmented else {
                    throw corrupt("contains a last fragment without a first fragment")
                }
                fragmented = nil
                try appendFragment(payload, to: &value)
                try append(value, to: &result, decodedByteCount: &decodedByteCount)
                fragmented = nil
            }
        }

        guard fragmented == nil else {
            throw corrupt("ends inside a fragmented record")
        }
        return result
    }
}

private extension FoundryLevelDBPhysicalLogReader {
    enum RecordType: UInt8 {
        case full = 1
        case first = 2
        case middle = 3
        case last = 4
    }

    func appendFragment(_ fragment: [UInt8], to value: inout [UInt8]) throws {
        let (nextCount, overflow) = value.count.addingReportingOverflow(fragment.count)
        guard !overflow, nextCount <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextCount)
        }
        value.append(contentsOf: fragment)
    }

    func append(
        _ record: [UInt8],
        to result: inout [[UInt8]],
        decodedByteCount: inout Int
    ) throws {
        let (nextByteCount, byteOverflow) = decodedByteCount.addingReportingOverflow(record.count)
        guard !byteOverflow, nextByteCount <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(byteOverflow ? Int.max : nextByteCount)
        }
        let (nextRecordCount, countOverflow) = result.count.addingReportingOverflow(1)
        guard !countOverflow, nextRecordCount <= limits.maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(countOverflow ? Int.max : nextRecordCount)
        }
        decodedByteCount = nextByteCount
        result.append(record)
    }

    func corrupt(_ reason: String) -> FoundryImportError {
        .corruptLevelDB("The \(context) \(reason).")
    }
}

/// Reads LevelDB WriteBatch records from a live numeric `.log` file.
struct FoundryLevelDBWriteAheadLogReader: Sendable {
    private static let writeBatchHeaderSize = 12
    private static let maximumSequenceNumber = (UInt64(1) << 56) - 1

    let limits: FoundryImportLimits

    init(limits: FoundryImportLimits = .default) {
        self.limits = limits
    }

    func records(in data: Data, path: String = "write-ahead log") throws -> [FoundryLevelDBRecord] {
        let batches = try FoundryLevelDBPhysicalLogReader(
            limits: limits,
            context: "LevelDB WAL \(path)"
        ).logicalRecords(in: data)
        var records: [FoundryLevelDBRecord] = []
        for batch in batches {
            try Task.checkCancellation()
            let decoded = try decodeWriteBatch(batch, path: path)
            let (nextCount, overflow) = records.count.addingReportingOverflow(decoded.count)
            guard !overflow, nextCount <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(overflow ? Int.max : nextCount)
            }
            records.append(contentsOf: decoded)
        }
        return records
    }
}

private extension FoundryLevelDBWriteAheadLogReader {
    func decodeWriteBatch(_ bytes: [UInt8], path: String) throws -> [FoundryLevelDBRecord] {
        guard bytes.count >= Self.writeBatchHeaderSize else {
            throw corrupt(path, "contains a truncated WriteBatch header")
        }
        let firstSequence = try bytes.littleEndianUInt64(at: 0)
        let rawCount = try bytes.littleEndianUInt32(at: 8)
        let count = Int(rawCount)
        guard count <= limits.maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(count)
        }
        guard firstSequence <= Self.maximumSequenceNumber else {
            throw corrupt(path, "contains a WriteBatch sequence outside LevelDB's 56-bit range")
        }
        if count > 0 {
            let sequenceIncrement = UInt64(count - 1)
            guard sequenceIncrement <= Self.maximumSequenceNumber - firstSequence else {
                throw corrupt(path, "contains a WriteBatch sequence range that overflows LevelDB's 56-bit range")
            }
        }

        var cursor = Self.writeBatchHeaderSize
        var records: [FoundryLevelDBRecord] = []
        records.reserveCapacity(count)
        for index in 0..<count {
            guard cursor < bytes.count else {
                throw corrupt(path, "contains fewer WriteBatch operations than its header declares")
            }
            let rawOperation = bytes[cursor]
            cursor += 1
            guard let operation = FoundryLevelDBRecord.Operation(rawValue: rawOperation) else {
                throw corrupt(path, "contains an unknown WriteBatch operation type \(rawOperation)")
            }

            let keyBytes = try readLengthPrefixedSlice(bytes, cursor: &cursor, path: path, field: "key")
            guard let key = String(bytes: keyBytes, encoding: .utf8) else {
                throw corrupt(path, "contains a WriteBatch key that is not UTF-8")
            }
            let value: ArraySlice<UInt8>
            switch operation {
            case .deletion:
                value = []
            case .value:
                value = try readLengthPrefixedSlice(bytes, cursor: &cursor, path: path, field: "value")
            }

            let (entrySize, entryOverflow) = keyBytes.count.addingReportingOverflow(value.count)
            guard !entryOverflow, entrySize <= limits.maximumEntrySize else {
                throw FoundryImportError.fileTooLarge(entryOverflow ? Int.max : entrySize)
            }
            records.append(FoundryLevelDBRecord(
                key: key,
                sequence: firstSequence + UInt64(index),
                operation: operation,
                value: Data(value)
            ))
        }
        guard cursor == bytes.count else {
            throw corrupt(path, "contains trailing bytes after its declared WriteBatch operations")
        }
        return records
    }

    func readLengthPrefixedSlice(
        _ bytes: [UInt8],
        cursor: inout Int,
        path: String,
        field: String
    ) throws -> ArraySlice<UInt8> {
        let length: UInt32
        do {
            length = try bytes.readVarint32(cursor: &cursor, limit: bytes.count)
        } catch {
            throw corrupt(path, "contains a truncated WriteBatch \(field) length")
        }
        let count = Int(length)
        guard count <= limits.maximumEntrySize else {
            throw FoundryImportError.fileTooLarge(count)
        }
        guard count <= bytes.count - cursor else {
            throw corrupt(path, "contains a truncated WriteBatch \(field)")
        }
        let end = cursor + count
        defer { cursor = end }
        return bytes[cursor..<end]
    }

    func corrupt(_ path: String, _ reason: String) -> FoundryImportError {
        .corruptLevelDB("The LevelDB WAL \(path) \(reason).")
    }
}
