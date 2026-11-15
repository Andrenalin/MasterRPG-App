// @copyright André Trettin

import Foundation
import zlib

/// A deliberately small ZIP reader for Foundry packages.
///
/// Foundry system archives only need regular files compressed with either the
/// stored or Deflate methods. Keeping this reader constrained also gives the
/// importer one place to enforce archive, entry, and path safety limits before
/// any untrusted data is decoded.
struct FoundryZIPArchive: Sendable {
    private struct Entry: Sendable {
        let path: String
        let flags: UInt16
        let compressionMethod: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private enum Signature {
        static let localFileHeader: UInt32 = 0x0403_4B50
        static let centralDirectoryHeader: UInt32 = 0x0201_4B50
        static let endOfCentralDirectory: UInt32 = 0x0605_4B50
    }

    private enum Layout {
        static let endOfCentralDirectorySize = 22
        static let maximumCommentSize = 65_535
        static let centralDirectoryHeaderSize = 46
        static let localFileHeaderSize = 30
    }

    /// The file a memory-mapped `archiveData` reads from, with its size and modification date at
    /// open. The mapping reads the file's pages on demand, so a file truncated or replaced during
    /// the import must be noticed before an entry is read from it. See CODE_AUDIT_26 §3.3.
    struct SourceStamp: Sendable, Equatable {
        let url: URL
        let fileSize: Int?
        let modificationDate: Date?

        init(url: URL) {
            self.url = url
            let values = Self.currentValues(of: url)
            fileSize = values?.fileSize
            modificationDate = values?.contentModificationDate
        }

        var isUnchanged: Bool {
            guard let values = Self.currentValues(of: url) else { return false }
            return values.fileSize == fileSize && values.contentModificationDate == modificationDate
        }

        /// Read through a fresh `URL`: a `URL` value caches the resource values it has read, so
        /// the same instance would report the size and date of the first read forever.
        private static func currentValues(of url: URL) -> URLResourceValues? {
            let fresh = URL(filePath: url.path(percentEncoded: false))
            return try? fresh.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        }
    }

    private let archiveData: Data
    private let sourceStamp: SourceStamp?
    private let entries: [Entry]
    private let entriesByPath: [String: Entry]

    var entryPaths: [String] {
        entries.map(\.path)
    }

    init(data: Data, limits: FoundryImportLimits = .default, sourceStamp: SourceStamp? = nil) throws {
        self.sourceStamp = sourceStamp
        guard data.count <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(data.count)
        }

        let endOffset = try Self.endOfCentralDirectoryOffset(in: data)
        let diskNumber = try data.littleEndianUInt16(at: endOffset + 4)
        let centralDirectoryDisk = try data.littleEndianUInt16(at: endOffset + 6)
        let entryCountOnDisk = try data.littleEndianUInt16(at: endOffset + 8)
        let entryCount = try data.littleEndianUInt16(at: endOffset + 10)
        let centralDirectorySizeValue = try data.littleEndianUInt32(at: endOffset + 12)
        let centralDirectoryOffsetValue = try data.littleEndianUInt32(at: endOffset + 16)

        guard diskNumber == 0,
              centralDirectoryDisk == 0,
              entryCountOnDisk == entryCount else {
            throw FoundryImportError.invalidArchive("Multi-disk ZIP archives are not supported.")
        }

        guard entryCount != UInt16.max,
              centralDirectorySizeValue != UInt32.max,
              centralDirectoryOffsetValue != UInt32.max else {
            throw FoundryImportError.invalidArchive("ZIP64 archives are not supported.")
        }

        let expectedEntryCount = Int(entryCount)
        guard expectedEntryCount <= limits.maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(expectedEntryCount)
        }

        let centralDirectoryOffset = Int(centralDirectoryOffsetValue)
        let centralDirectorySize = Int(centralDirectorySizeValue)
        let (centralDirectoryEnd, centralDirectoryOverflow) = centralDirectoryOffset.addingReportingOverflow(centralDirectorySize)
        guard !centralDirectoryOverflow,
              centralDirectoryOffset >= 0,
              centralDirectoryEnd == endOffset else {
            throw FoundryImportError.invalidArchive("The central directory has invalid bounds.")
        }

        var parsedEntries: [Entry] = []
        parsedEntries.reserveCapacity(expectedEntryCount)
        var knownPaths = Set<String>()
        var totalUncompressedSize = 0
        var cursor = centralDirectoryOffset

        for _ in 0..<expectedEntryCount {
            try Task.checkCancellation()
            try data.requireRange(offset: cursor, count: Layout.centralDirectoryHeaderSize)
            guard try data.littleEndianUInt32(at: cursor) == Signature.centralDirectoryHeader else {
                throw FoundryImportError.invalidArchive("A central directory entry has an invalid signature.")
            }

            let versionMadeBy = try data.littleEndianUInt16(at: cursor + 4)
            let flags = try data.littleEndianUInt16(at: cursor + 8)
            let compressionMethod = try data.littleEndianUInt16(at: cursor + 10)
            let checksum = try data.littleEndianUInt32(at: cursor + 16)
            let compressedSizeValue = try data.littleEndianUInt32(at: cursor + 20)
            let uncompressedSizeValue = try data.littleEndianUInt32(at: cursor + 24)
            let nameLength = Int(try data.littleEndianUInt16(at: cursor + 28))
            let extraLength = Int(try data.littleEndianUInt16(at: cursor + 30))
            let commentLength = Int(try data.littleEndianUInt16(at: cursor + 32))
            let startingDisk = try data.littleEndianUInt16(at: cursor + 34)
            let externalAttributes = try data.littleEndianUInt32(at: cursor + 38)
            let localHeaderOffsetValue = try data.littleEndianUInt32(at: cursor + 42)

            guard flags & 0x2041 == 0 else {
                throw FoundryImportError.encryptedArchive
            }
            guard compressionMethod == 0 || compressionMethod == 8 else {
                throw FoundryImportError.unsupportedZIPCompression(compressionMethod)
            }
            guard startingDisk == 0 else {
                throw FoundryImportError.invalidArchive("Multi-disk ZIP entries are not supported.")
            }
            guard compressedSizeValue != UInt32.max,
                  uncompressedSizeValue != UInt32.max,
                  localHeaderOffsetValue != UInt32.max else {
                throw FoundryImportError.invalidArchive("ZIP64 entries are not supported.")
            }
            guard nameLength > 0 else {
                throw FoundryImportError.invalidArchive("ZIP entries must have a path.")
            }

            let variableLength = try Self.checkedSum(nameLength, extraLength, commentLength)
            let entryLength = try Self.checkedSum(Layout.centralDirectoryHeaderSize, variableLength)
            try data.requireRange(offset: cursor, count: entryLength)
            guard cursor + entryLength <= centralDirectoryEnd else {
                throw FoundryImportError.invalidArchive("A central directory entry exceeds the directory bounds.")
            }

            let nameData = data.subdata(in: (cursor + Layout.centralDirectoryHeaderSize)..<(cursor + Layout.centralDirectoryHeaderSize + nameLength))
            let path = try Self.decodeAndValidatePath(nameData, flags: flags)
            guard knownPaths.insert(path.precomposedStringWithCanonicalMapping).inserted else {
                throw FoundryImportError.invalidArchive("The archive contains a duplicate path: \(path)")
            }

            let extraOffset = cursor + Layout.centralDirectoryHeaderSize + nameLength
            try Self.validateExtraFields(in: data, offset: extraOffset, count: extraLength)
            try Self.validateFileType(versionMadeBy: versionMadeBy, externalAttributes: externalAttributes, path: path)

            let compressedSize = Int(compressedSizeValue)
            let uncompressedSize = Int(uncompressedSizeValue)
            guard uncompressedSize <= limits.maximumEntrySize else {
                throw FoundryImportError.fileTooLarge(uncompressedSize)
            }
            let (nextTotal, totalOverflow) = totalUncompressedSize.addingReportingOverflow(uncompressedSize)
            guard !totalOverflow, nextTotal <= limits.maximumRuleDataSize else {
                throw FoundryImportError.fileTooLarge(totalOverflow ? Int.max : nextTotal)
            }
            totalUncompressedSize = nextTotal

            if compressionMethod == 0, compressedSize != uncompressedSize {
                throw FoundryImportError.invalidArchive("Stored entry \(path) has inconsistent sizes.")
            }

            let entry = Entry(
                path: path,
                flags: flags,
                compressionMethod: compressionMethod,
                crc32: checksum,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: Int(localHeaderOffsetValue)
            )
            try Self.validateLocalHeader(for: entry, in: data, centralDirectoryOffset: centralDirectoryOffset)
            parsedEntries.append(entry)
            cursor += entryLength
        }

        guard cursor == centralDirectoryEnd else {
            throw FoundryImportError.invalidArchive("The central directory contains unsupported trailing records.")
        }

        archiveData = data
        entries = parsedEntries
        entriesByPath = Dictionary(uniqueKeysWithValues: parsedEntries.map { ($0.path, $0) })
    }

    func contains(path: String) -> Bool {
        entriesByPath[path] != nil
    }

    func paths(matching predicate: (String) throws -> Bool) rethrows -> [String] {
        try entryPaths.filter(predicate)
    }

    func data(forPath path: String) throws -> Data? {
        guard let entry = entriesByPath[path] else { return nil }
        if let sourceStamp, !sourceStamp.isUnchanged {
            throw FoundryImportError.invalidArchive("The source file changed during the import.")
        }

        let payloadOffset = try Self.payloadOffset(for: entry, in: archiveData)
        let compressedData = archiveData.subdata(in: payloadOffset..<(payloadOffset + entry.compressedSize))
        let result: Data

        switch entry.compressionMethod {
        case 0:
            result = compressedData
        case 8:
            result = try Self.inflateRawDeflate(compressedData, expectedSize: entry.uncompressedSize, path: entry.path)
        default:
            throw FoundryImportError.unsupportedZIPCompression(entry.compressionMethod)
        }

        guard result.count == entry.uncompressedSize else {
            throw FoundryImportError.invalidArchive("Entry \(entry.path) decoded to an unexpected size.")
        }
        guard Self.checksum(of: result) == entry.crc32 else {
            throw FoundryImportError.invalidArchive("Entry \(entry.path) failed its CRC-32 check.")
        }
        return result
    }
}

private extension FoundryZIPArchive {
    static func endOfCentralDirectoryOffset(in data: Data) throws -> Int {
        guard data.count >= Layout.endOfCentralDirectorySize else {
            throw FoundryImportError.invalidArchive("The end-of-central-directory record is missing.")
        }

        let earliestOffset = max(0, data.count - Layout.endOfCentralDirectorySize - Layout.maximumCommentSize)
        var candidate = data.count - Layout.endOfCentralDirectorySize
        while candidate >= earliestOffset {
            if try data.littleEndianUInt32(at: candidate) == Signature.endOfCentralDirectory {
                let commentLength = Int(try data.littleEndianUInt16(at: candidate + 20))
                if candidate + Layout.endOfCentralDirectorySize + commentLength == data.count {
                    return candidate
                }
            }
            candidate -= 1
        }
        throw FoundryImportError.invalidArchive("The end-of-central-directory record is missing.")
    }

    static func decodeAndValidatePath(_ data: Data, flags: UInt16) throws -> String {
        // Foundry emits UTF-8/ASCII paths. Accepting an unknown legacy code page
        // would make path identity ambiguous and could undermine traversal checks.
        guard let path = String(data: data, encoding: .utf8) else {
            let encodingDescription = flags & 0x0800 == 0 ? "legacy" : "UTF-8"
            throw FoundryImportError.invalidArchive("A ZIP entry has an invalid \(encodingDescription) path encoding.")
        }
        guard path.utf8.count <= 4_096 else {
            throw FoundryImportError.invalidArchive("A ZIP entry path is too long.")
        }
        guard !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\"),
              !path.contains("\0") else {
            throw FoundryImportError.invalidArchive("ZIP entry path \(path.debugDescription) is unsafe.")
        }

        var components = path.split(separator: "/", omittingEmptySubsequences: false)
        if components.last?.isEmpty == true {
            components.removeLast()
        }
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw FoundryImportError.invalidArchive("ZIP entry path \(path.debugDescription) is unsafe.")
        }
        if let first = components.first,
           first.count == 2,
           first.last == ":",
           first.first?.isASCII == true,
           first.first?.isLetter == true {
            throw FoundryImportError.invalidArchive("ZIP entry path \(path.debugDescription) is absolute.")
        }
        return path
    }

    static func validateExtraFields(in data: Data, offset: Int, count: Int) throws {
        var cursor = offset
        let end = offset + count
        while cursor < end {
            guard end - cursor >= 4 else {
                throw FoundryImportError.invalidArchive("A ZIP extra field is malformed.")
            }
            let identifier = try data.littleEndianUInt16(at: cursor)
            let payloadSize = Int(try data.littleEndianUInt16(at: cursor + 2))
            guard payloadSize <= end - cursor - 4 else {
                throw FoundryImportError.invalidArchive("A ZIP extra field exceeds its entry bounds.")
            }
            guard identifier != 0x0001 else {
                throw FoundryImportError.invalidArchive("ZIP64 entries are not supported.")
            }
            cursor += 4 + payloadSize
        }
    }

    static func validateFileType(versionMadeBy: UInt16, externalAttributes: UInt32, path: String) throws {
        let hostSystem = UInt8(truncatingIfNeeded: versionMadeBy >> 8)
        guard hostSystem == 3 || hostSystem == 19 else { return }

        let unixMode = UInt16(truncatingIfNeeded: externalAttributes >> 16)
        let fileType = unixMode & 0xF000
        guard fileType != 0xA000 else {
            throw FoundryImportError.invalidArchive("Symbolic link entry \(path) is not supported.")
        }
    }

    private static func validateLocalHeader(for entry: Entry, in data: Data, centralDirectoryOffset: Int) throws {
        let offset = entry.localHeaderOffset
        try data.requireRange(offset: offset, count: Layout.localFileHeaderSize)
        guard offset < centralDirectoryOffset,
              try data.littleEndianUInt32(at: offset) == Signature.localFileHeader else {
            throw FoundryImportError.invalidArchive("Entry \(entry.path) has an invalid local header.")
        }

        let localFlags = try data.littleEndianUInt16(at: offset + 6)
        let localMethod = try data.littleEndianUInt16(at: offset + 8)
        let localChecksum = try data.littleEndianUInt32(at: offset + 14)
        let localCompressedSize = try data.littleEndianUInt32(at: offset + 18)
        let localUncompressedSize = try data.littleEndianUInt32(at: offset + 22)
        let nameLength = Int(try data.littleEndianUInt16(at: offset + 26))
        let extraLength = Int(try data.littleEndianUInt16(at: offset + 28))

        guard localFlags == entry.flags,
              localMethod == entry.compressionMethod else {
            throw FoundryImportError.invalidArchive("Entry \(entry.path) has inconsistent local metadata.")
        }
        guard localFlags & 0x2041 == 0 else {
            throw FoundryImportError.encryptedArchive
        }

        let headerLength = try checkedSum(Layout.localFileHeaderSize, nameLength, extraLength)
        try data.requireRange(offset: offset, count: headerLength)
        let pathData = data.subdata(in: (offset + Layout.localFileHeaderSize)..<(offset + Layout.localFileHeaderSize + nameLength))
        let localPath = try decodeAndValidatePath(pathData, flags: localFlags)
        guard localPath == entry.path else {
            throw FoundryImportError.invalidArchive("Entry \(entry.path) has mismatched local and central paths.")
        }

        let extraOffset = offset + Layout.localFileHeaderSize + nameLength
        try validateExtraFields(in: data, offset: extraOffset, count: extraLength)

        if localFlags & 0x0008 == 0 {
            guard localChecksum == entry.crc32,
                  localCompressedSize == UInt32(entry.compressedSize),
                  localUncompressedSize == UInt32(entry.uncompressedSize) else {
                throw FoundryImportError.invalidArchive("Entry \(entry.path) has inconsistent local sizes or checksum.")
            }
        } else {
            guard (localChecksum == 0 || localChecksum == entry.crc32),
                  (localCompressedSize == 0 || localCompressedSize == UInt32(entry.compressedSize)),
                  (localUncompressedSize == 0 || localUncompressedSize == UInt32(entry.uncompressedSize)) else {
                throw FoundryImportError.invalidArchive("Entry \(entry.path) has inconsistent data-descriptor metadata.")
            }
        }

        let payloadOffset = offset + headerLength
        let (payloadEnd, payloadOverflow) = payloadOffset.addingReportingOverflow(entry.compressedSize)
        guard !payloadOverflow,
              payloadEnd <= centralDirectoryOffset else {
            throw FoundryImportError.invalidArchive("Entry \(entry.path) data exceeds the archive bounds.")
        }
    }

    private static func payloadOffset(for entry: Entry, in data: Data) throws -> Int {
        let nameLength = Int(try data.littleEndianUInt16(at: entry.localHeaderOffset + 26))
        let extraLength = Int(try data.littleEndianUInt16(at: entry.localHeaderOffset + 28))
        return try checkedSum(entry.localHeaderOffset, Layout.localFileHeaderSize, nameLength, extraLength)
    }

    static func inflateRawDeflate(_ compressedData: Data, expectedSize: Int, path: String) throws -> Data {
        var stream = z_stream()
        let initializationResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initializationResult == Z_OK else {
            throw FoundryImportError.invalidArchive("Could not initialize Deflate decoding for \(path).")
        }
        defer { inflateEnd(&stream) }

        var output = [UInt8](repeating: 0, count: max(expectedSize, 1))
        let result = compressedData.withUnsafeBytes { compressedBuffer -> Int32 in
            output.withUnsafeMutableBytes { outputBuffer -> Int32 in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: compressedBuffer.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(compressedBuffer.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputBuffer.count)
                return inflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END,
              stream.total_in == compressedData.count,
              stream.total_out == expectedSize else {
            throw FoundryImportError.invalidArchive("Entry \(path) contains invalid Deflate data.")
        }
        return Data(output.prefix(expectedSize))
    }

    static func checksum(of data: Data) -> UInt32 {
        let initial = crc32(0, nil, 0)
        let value = data.withUnsafeBytes { buffer in
            crc32(initial, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count))
        }
        return UInt32(truncatingIfNeeded: value)
    }

    static func checkedSum(_ values: Int...) throws -> Int {
        var total = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow, value >= 0 else {
                throw FoundryImportError.invalidArchive("A ZIP record length overflowed.")
            }
            total = next
        }
        return total
    }
}

private extension Data {
    func requireRange(offset: Int, count: Int) throws {
        let (end, overflow) = offset.addingReportingOverflow(count)
        guard offset >= 0,
              count >= 0,
              !overflow,
              end <= self.count else {
            throw FoundryImportError.invalidArchive("A ZIP record exceeds the archive bounds.")
        }
    }

    func littleEndianUInt16(at offset: Int) throws -> UInt16 {
        try requireRange(offset: offset, count: 2)
        let first = self[index(startIndex, offsetBy: offset)]
        let second = self[index(startIndex, offsetBy: offset + 1)]
        return UInt16(first) | UInt16(second) << 8
    }

    func littleEndianUInt32(at offset: Int) throws -> UInt32 {
        try requireRange(offset: offset, count: 4)
        let first = UInt32(self[index(startIndex, offsetBy: offset)])
        let second = UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 8
        let third = UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 16
        let fourth = UInt32(self[index(startIndex, offsetBy: offset + 3)]) << 24
        return first | second | third | fourth
    }
}
