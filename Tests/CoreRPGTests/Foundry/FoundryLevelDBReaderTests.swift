// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("Foundry LevelDB table reader")
struct FoundryLevelDBReaderTests {
    @Test("Decodes raw Snappy vectors", arguments: SnappyVector.cases)
    func decodesSnappyVector(vector: SnappyVector) throws {
        // Given
        let decoder = FoundrySnappyDecoder(maximumOutputSize: 1_024)

        // When
        let decoded = try decoder.decode(vector.encoded)

        // Then
        #expect(decoded == vector.decoded)
    }

    @Test("CRC32C matches the standard check vector")
    func crc32CCheckVector() {
        // Given
        let bytes = Array("123456789".utf8)

        // When / Then
        #expect(FoundryCRC32C.checksum(bytes) == 0xe306_9283)
        #expect(FoundryCRC32C.maskedChecksum(bytes) == 0xc78a_b0e5)
    }

    @Test("Decodes uncompressed and Snappy-compressed SSTables", arguments: [false, true])
    func decodesTable(compressDataBlock: Bool) throws {
        // Given
        let expected = [
            FoundryLevelDBRecord(
                key: "!items!alpha",
                sequence: 17,
                operation: .value,
                value: Data(#"{"_id":"alpha","name":"Alpha"}"#.utf8)
            ),
            FoundryLevelDBRecord(
                key: "!items!alphabet",
                sequence: 9,
                operation: .deletion,
                value: Data()
            ),
        ]
        let table = FoundryLevelDBFixture.table(
            records: expected,
            compressDataBlock: compressDataBlock
        )

        // When
        let records = try FoundryLevelDBTableReader().records(in: table)

        // Then
        #expect(records == expected)
    }

    @Test("Rejects cumulative decoded blocks above the table budget")
    func rejectsCumulativeDecodedBlockSize() {
        // Given
        let record = FoundryLevelDBRecord(
            key: "!items!compressed",
            sequence: 1,
            operation: .value,
            value: Data(repeating: 0x61, count: 512)
        )
        let table = FoundryLevelDBFixture.table(records: [record], compressDataBlock: true)
        let limits = FoundryImportLimits(
            maximumArchiveSize: 4_096,
            maximumEntrySize: 4_096,
            maximumRuleDataSize: table.count,
            maximumDocumentCount: 10
        )

        // When
        var rejectedDecodedSize: Int?
        do {
            _ = try FoundryLevelDBTableReader(limits: limits).records(in: table)
        } catch FoundryImportError.fileTooLarge(let size) {
            rejectedDecodedSize = size
        } catch {
            // The assertions below report an unexpected error without obscuring its type.
        }

        // Then
        #expect(rejectedDecodedSize != nil)
        #expect((rejectedDecodedSize ?? 0) > table.count)
    }

    @Test("Rejects a block whose checksum was changed")
    func rejectsChecksumMismatch() {
        // Given
        let record = FoundryLevelDBRecord(
            key: "!items!alpha",
            sequence: 1,
            operation: .value,
            value: Data("value".utf8)
        )
        var bytes = Array(FoundryLevelDBFixture.table(records: [record]))
        bytes[0] ^= 0xff

        // When / Then
        #expect(throws: FoundryImportError.corruptLevelDB("A block checksum does not match.")) {
            try FoundryLevelDBTableReader().records(in: Data(bytes))
        }
    }

    @Test("Rejects trailing bytes in an index block handle")
    func rejectsTrailingIndexHandleBytes() {
        // Given
        let record = FoundryLevelDBRecord(
            key: "!items!alpha",
            sequence: 1,
            operation: .value,
            value: Data("value".utf8)
        )
        let table = FoundryLevelDBFixture.table(records: [record], indexValueSuffix: [0])

        // When / Then
        #expect(throws: FoundryImportError.corruptLevelDB("An index entry contains an invalid block handle.")) {
            try FoundryLevelDBTableReader().records(in: table)
        }
    }

    @Test("Rejects a restart offset that is not an entry boundary")
    func rejectsInvalidRestartBoundary() {
        // Given
        let record = FoundryLevelDBRecord(
            key: "!items!alpha",
            sequence: 1,
            operation: .value,
            value: Data("value".utf8)
        )
        let table = FoundryLevelDBFixture.table(records: [record], dataRestartOffsets: [0, 1])

        // When / Then
        #expect(throws: FoundryImportError.corruptLevelDB("A data block restart does not point to an entry.")) {
            try FoundryLevelDBTableReader().records(in: table)
        }
    }

    @Test("Rejects a block handle that points into the footer")
    func rejectsFooterBlockHandle() {
        // Given
        let table = FoundryLevelDBFixture.tableWithIndexHandleInFooter()

        // When / Then
        #expect(throws: FoundryImportError.corruptLevelDB("A block points outside its table.")) {
            try FoundryLevelDBTableReader().records(in: table)
        }
    }

    @Test("Rejects invalid Snappy copy offsets and output sizes")
    func rejectsInvalidSnappyInput() {
        // Given
        let decoder = FoundrySnappyDecoder(maximumOutputSize: 4)

        // When / Then
        #expect(throws: FoundryImportError.corruptLevelDB("A Snappy copy points outside its decoded data.")) {
            try decoder.decode([1, 1, 0])
        }
        #expect(throws: FoundryImportError.fileTooLarge(5)) {
            try decoder.decode([5])
        }
    }
}

@Suite("Foundry system package reader")
struct FoundrySystemPackageReaderTests {
    @Test("Reads rules and packaged resources from an extracted system")
    func readsExtractedSystem() async throws {
        // Given
        let root = URL.temporaryDirectory.appending(
            path: "FoundrySystemPackageReaderTests-\(UUID())",
            directoryHint: .isDirectory
        )
        let packDirectory = root.appending(path: "packs/spells", directoryHint: .isDirectory)
        let iconDirectory = root.appending(path: "icons", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let assetData = Data("synthetic-webp".utf8)
        try Self.write(Self.manifestJSON, to: root.appending(path: "system.json"))
        try Self.write(Self.templateJSON, to: root.appending(path: "template.json"))
        try Self.write("Test content license", to: root.appending(path: "LICENSE.md"))
        try assetData.write(to: iconDirectory.appending(path: "spark.webp"), options: .atomic)

        let records = [
            FoundryLevelDBRecord(
                key: "!items!spell001",
                sequence: 2,
                operation: .value,
                value: Data(Self.ruleJSON.utf8)
            ),
            FoundryLevelDBRecord(
                key: "!items.effects!spell001.effect01",
                sequence: 1,
                operation: .value,
                value: Data(Self.effectJSON.utf8)
            ),
        ]
        try FoundryLevelDBFixture.table(records: records, compressDataBlock: true)
            .write(to: packDirectory.appending(path: "000005.ldb"), options: .atomic)

        // When
        let package = try await FoundrySystemPackageReader().read(from: root)

        // Then
        #expect(package.manifest.id == "ds4")
        #expect(package.manifest.version == "1.0.0")
        #expect(package.manifestPath == "system.json")
        #expect(package.templatePath == "template.json")
        #expect(package.ruleCount == 1)
        #expect(package.assetPaths == ["systems/ds4/icons/spark.webp"])
        #expect(package.licensePaths == ["LICENSE.md"])

        let resource = try #require(package.resources.first)
        #expect(package.resources.count == 1)
        #expect(resource.logicalPath == "systems/ds4/icons/spark.webp")
        #expect(resource.packagePath == "icons/spark.webp")
        #expect(resource.location == .packaged)
        #expect(resource.byteCount == 14)
        #expect(resource.sha256 == "0ce6f8c398602d6806ab08c83f778eb121339007b91b5c2b4a8ac640c71a175c")
        let reopenedAsset = try await FoundrySystemPackageReader().readResource(
            resource,
            from: root,
            in: package
        )
        #expect(reopenedAsset == assetData)

        var duplicateRequestError: FoundryImportError?
        do {
            _ = try await FoundrySystemPackageReader().readResources(
                [resource, resource],
                from: root,
                in: package
            )
        } catch let error as FoundryImportError {
            duplicateRequestError = error
        }
        #expect(duplicateRequestError == .duplicateResourceRequest)

        let constrainedReader = FoundrySystemPackageReader(limits: FoundryImportLimits(
            maximumResourceBatchSize: assetData.count - 1
        ))
        var resourceLimitError: FoundryImportError?
        do {
            _ = try await constrainedReader.readResource(resource, from: root, in: package)
        } catch let error as FoundryImportError {
            resourceLimitError = error
        }
        #expect(resourceLimitError == .fileTooLarge(assetData.count))

        let schema = try #require(package.schemas.first)
        #expect(schema.id == "Item.spell")
        #expect(schema.inheritedTemplates == ["magic"])
        let fieldPaths = Set(schema.fields.map(\.path))
        #expect(fieldPaths.contains("system.description"))
        #expect(fieldPaths.contains("system.rank.base"))
        #expect(fieldPaths.contains("system.spellGroups.fire"))
        #expect(fieldPaths.contains("system.spellType"))

        let rule = try #require(package.rules.first)
        #expect(rule.id == "foundry://system/ds4/pack/spells/Item/spell001")
        #expect(rule.name == "Spark")
        #expect(rule.category == .spell)
        #expect(rule.descriptionHTML?.contains("@Compendium") == true)
        #expect(rule.tags == ["fire"])

        let reference = try #require(rule.references.first)
        #expect(reference.kind == .compendium)
        #expect(reference.sourcePath == "system.description")
        #expect(reference.packName == "spells")
        #expect(reference.documentId == "spell002")
        #expect(reference.label == "Fireball")

        let effect = try #require(rule.effects.first)
        #expect(effect.name == "Burning")
        #expect(effect.transfersToActor)
        #expect(effect.statuses == ["burning"])
        let change = try #require(effect.changes.first)
        #expect(change.path == "system.rank.base")
        #expect(change.mode == 2)
        #expect(change.operand == .integer(1))
        #expect(change.priority == 10)

        #expect(package.diagnostics.contains { $0.code == "rules-decoded" })
    }

    @Test("Rejects a pack with more than one LevelDB table")
    func rejectsMultipleLevelDBTables() async throws {
        // Given
        let root = URL.temporaryDirectory.appending(
            path: "FoundrySystemPackageReaderTableSetTests-\(UUID())",
            directoryHint: .isDirectory
        )
        let packDirectory = root.appending(path: "packs/spells", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.write(Self.manifestJSON, to: root.appending(path: "system.json"))
        try Data([0]).write(to: packDirectory.appending(path: "000005.ldb"), options: .atomic)
        try Data([0]).write(to: packDirectory.appending(path: "000006.ldb"), options: .atomic)

        // When
        var receivedError: FoundryImportError?
        do {
            _ = try await FoundrySystemPackageReader().read(from: root)
        } catch let error as FoundryImportError {
            receivedError = error
        }

        // Then
        #expect(receivedError == .unsupportedLevelDBTableSet(pack: "spells", tableCount: 2))
    }

    @Test("Rejects duplicate compendium names and normalized paths")
    func rejectsDuplicatePackDeclarations() async throws {
        // Given / When
        let duplicateNameError = try await Self.importError(for: Self.duplicatePackNameManifestJSON)
        let duplicatePathError = try await Self.importError(for: Self.duplicatePackPathManifestJSON)

        // Then
        #expect(duplicateNameError == .invalidManifest(
            "The compendium name duplicate is declared more than once."
        ))
        #expect(duplicatePathError == .invalidManifest(
            "The compendium path packs//./shared is declared more than once."
        ))
    }
}

private extension FoundrySystemPackageReaderTests {
    static let manifestJSON = #"""
    {
      "id": "ds4",
      "title": "Synthetic DS4",
      "version": "1.0.0",
      "compatibility": { "minimum": "12", "verified": "12" },
      "packs": [
        {
          "name": "spells",
          "label": "Spells",
          "path": "./packs/spells",
          "type": "Item",
          "system": "ds4"
        }
      ]
    }
    """#

    static let duplicatePackNameManifestJSON = #"""
    {
      "id": "ds4",
      "title": "Duplicate Name",
      "version": "1.0.0",
      "packs": [
        { "name": "duplicate", "path": "./packs/one", "type": "Item" },
        { "name": "duplicate", "path": "./packs/two", "type": "Item" }
      ]
    }
    """#

    static let duplicatePackPathManifestJSON = #"""
    {
      "id": "ds4",
      "title": "Duplicate Path",
      "version": "1.0.0",
      "packs": [
        { "name": "one", "path": "./packs/shared", "type": "Item" },
        { "name": "two", "path": "packs//./shared", "type": "Item" }
      ]
    }
    """#

    static let templateJSON = #"""
    {
      "Item": {
        "types": ["spell"],
        "templates": {
          "base": {
            "description": "",
            "rank": { "base": 0 }
          },
          "magic": {
            "templates": ["base"],
            "spellGroups": { "fire": false }
          }
        },
        "spell": {
          "templates": ["magic"],
          "spellType": "unset"
        }
      }
    }
    """#

    static let ruleJSON = #"""
    {
      "_id": "spell001",
      "name": "Spark",
      "type": "spell",
      "img": "systems/ds4/icons/spark.webp",
      "folder": null,
      "system": {
        "description": "Use @Compendium[ds4.spells.spell002]{Fireball}.",
        "spellType": "targeted",
        "spellGroups": { "fire": true },
        "rank": { "base": 1 }
      }
    }
    """#

    static let effectJSON = #"""
    {
      "_id": "effect01",
      "name": "Burning",
      "disabled": false,
      "transfer": true,
      "statuses": ["burning"],
      "changes": [
        {
          "key": "system.rank.base",
          "mode": 2,
          "value": 1,
          "priority": 10
        }
      ],
      "duration": { "rounds": 1 }
    }
    """#

    static func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url, options: .atomic)
    }

    static func importError(for manifest: String) async throws -> FoundryImportError? {
        let root = URL.temporaryDirectory.appending(
            path: "FoundrySystemPackageReaderInvalidManifestTests-\(UUID())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write(manifest, to: root.appending(path: "system.json"))

        do {
            _ = try await FoundrySystemPackageReader().read(from: root)
            return nil
        } catch let error as FoundryImportError {
            return error
        }
    }
}

struct SnappyVector: Sendable, CustomTestStringConvertible {
    let name: String
    let encoded: [UInt8]
    let decoded: [UInt8]

    var testDescription: String { name }

    static let cases: [Self] = {
        let eightBytes = Array("abcdefgh".utf8)
        let longLiteral = [UInt8](repeating: 0x78, count: 61)
        return [
            Self(name: "empty", encoded: [0], decoded: []),
            Self(
                name: "short literal",
                encoded: [5, 0x10] + Array("hello".utf8),
                decoded: Array("hello".utf8)
            ),
            Self(
                name: "one-byte copy",
                encoded: [16, 0x1c] + eightBytes + [0x11, 8],
                decoded: eightBytes + eightBytes
            ),
            Self(
                name: "overlapping two-byte copy",
                encoded: [12, 0x08] + Array("abc".utf8) + [0x22, 3, 0],
                decoded: Array("abcabcabcabc".utf8)
            ),
            Self(
                name: "four-byte copy",
                encoded: [16, 0x1c] + eightBytes + [0x1f, 8, 0, 0, 0],
                decoded: eightBytes + eightBytes
            ),
            Self(
                name: "long literal",
                encoded: [61, 0xf0, 60] + longLiteral,
                decoded: longLiteral
            ),
        ]
    }()
}

enum FoundryLevelDBFixture {
    private static let tableMagicNumber: UInt64 = 0xdb47_7524_8b80_fb57

    static func table(
        records: [FoundryLevelDBRecord],
        compressDataBlock: Bool = false,
        indexValueSuffix: [UInt8] = [],
        dataRestartOffsets: [Int] = [0]
    ) -> Data {
        let entries = records.map { record in
            Entry(
                key: internalKey(for: record),
                value: Array(record.value)
            )
        }
        let dataBlock = block(entries: entries, restartOffsets: dataRestartOffsets)

        var table: [UInt8] = []
        let dataHandle = appendStoredBlock(dataBlock, compress: compressDataBlock, to: &table)
        let metaIndexHandle = appendStoredBlock(block(entries: []), compress: false, to: &table)

        var indexValue: [UInt8] = []
        appendVarint(UInt64(dataHandle.offset), to: &indexValue)
        appendVarint(UInt64(dataHandle.size), to: &indexValue)
        indexValue.append(contentsOf: indexValueSuffix)
        let indexKey = entries.last?.key ?? [0]
        let indexBlock = block(entries: [Entry(key: indexKey, value: indexValue)])
        let indexHandle = appendStoredBlock(indexBlock, compress: false, to: &table)

        appendFooter(metaIndexHandle: metaIndexHandle, indexHandle: indexHandle, to: &table)
        return Data(table)
    }

    static func tableWithIndexHandleInFooter() -> Data {
        var table = [UInt8](repeating: 0, count: 5)
        let footerOffset = table.count
        appendFooter(
            metaIndexHandle: Handle(offset: 0, size: 0),
            indexHandle: Handle(offset: footerOffset, size: 0),
            to: &table
        )
        return Data(table)
    }
}

private extension FoundryLevelDBFixture {
    struct Entry {
        let key: [UInt8]
        let value: [UInt8]
    }

    struct Handle {
        let offset: Int
        let size: Int
    }

    static func internalKey(for record: FoundryLevelDBRecord) -> [UInt8] {
        var key = Array(record.key.utf8)
        appendLittleEndian((record.sequence << 8) | UInt64(record.operation.rawValue), to: &key)
        return key
    }

    static func block(entries: [Entry], restartOffsets: [Int] = [0]) -> [UInt8] {
        var result: [UInt8] = []
        var previousKey: [UInt8] = []
        for entry in entries {
            let sharedLength = commonPrefixLength(previousKey, entry.key)
            let unsharedKey = entry.key.dropFirst(sharedLength)
            appendVarint(UInt64(sharedLength), to: &result)
            appendVarint(UInt64(unsharedKey.count), to: &result)
            appendVarint(UInt64(entry.value.count), to: &result)
            result.append(contentsOf: unsharedKey)
            result.append(contentsOf: entry.value)
            previousKey = entry.key
        }
        for restartOffset in restartOffsets {
            appendLittleEndian(UInt32(restartOffset), to: &result)
        }
        appendLittleEndian(UInt32(restartOffsets.count), to: &result)
        return result
    }

    static func appendStoredBlock(_ block: [UInt8], compress: Bool, to table: inout [UInt8]) -> Handle {
        let compression: UInt8 = compress ? 1 : 0
        let content = compress ? snappyRunCompressed(block) : block
        let handle = Handle(offset: table.count, size: content.count)
        table.append(contentsOf: content)
        table.append(compression)
        appendLittleEndian(FoundryCRC32C.maskedChecksum(content + [compression]), to: &table)
        return handle
    }

    static func appendFooter(metaIndexHandle: Handle, indexHandle: Handle, to table: inout [UInt8]) {
        var footer: [UInt8] = []
        appendVarint(UInt64(metaIndexHandle.offset), to: &footer)
        appendVarint(UInt64(metaIndexHandle.size), to: &footer)
        appendVarint(UInt64(indexHandle.offset), to: &footer)
        appendVarint(UInt64(indexHandle.size), to: &footer)
        footer.append(contentsOf: repeatElement(0, count: 40 - footer.count))
        appendLittleEndian(tableMagicNumber, to: &footer)
        table.append(contentsOf: footer)
    }

    static func snappyRunCompressed(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        appendVarint(UInt64(bytes.count), to: &result)
        guard !bytes.isEmpty else { return result }

        var literalStart = 0
        var index = 0
        while index < bytes.count {
            var runEnd = index + 1
            while runEnd < bytes.count, bytes[runEnd] == bytes[index] {
                runEnd += 1
            }
            let runLength = runEnd - index
            if runLength >= 8 {
                appendSnappyLiteral(bytes[literalStart...index], to: &result)
                var remaining = runLength - 1
                while remaining > 0 {
                    let copyLength = min(remaining, 64)
                    result.append(UInt8(((copyLength - 1) << 2) | 2))
                    result.append(1)
                    result.append(0)
                    remaining -= copyLength
                }
                literalStart = runEnd
            }
            index = runEnd
        }
        if literalStart < bytes.count {
            appendSnappyLiteral(bytes[literalStart...], to: &result)
        }
        return result
    }

    static func appendSnappyLiteral(_ literal: ArraySlice<UInt8>, to result: inout [UInt8]) {
        guard !literal.isEmpty else { return }
        if literal.count < 61 {
            result.append(UInt8((literal.count - 1) << 2))
        } else {
            var lengthMinusOne = UInt32(literal.count - 1)
            var lengthBytes: [UInt8] = []
            repeat {
                lengthBytes.append(UInt8(lengthMinusOne & 0xff))
                lengthMinusOne >>= 8
            } while lengthMinusOne > 0
            result.append(UInt8((59 + lengthBytes.count) << 2))
            result.append(contentsOf: lengthBytes)
        }
        result.append(contentsOf: literal)
    }

    static func appendVarint(_ value: UInt64, to bytes: inout [UInt8]) {
        var remaining = value
        while remaining >= 0x80 {
            bytes.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        bytes.append(UInt8(remaining))
    }

    static func appendLittleEndian(_ value: UInt32, to bytes: inout [UInt8]) {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8((value >> UInt32(shift)) & 0xff))
        }
    }

    static func appendLittleEndian(_ value: UInt64, to bytes: inout [UInt8]) {
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }

    static func commonPrefixLength(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        var index = 0
        while index < lhs.count, index < rhs.count, lhs[index] == rhs[index] {
            index += 1
        }
        return index
    }
}
