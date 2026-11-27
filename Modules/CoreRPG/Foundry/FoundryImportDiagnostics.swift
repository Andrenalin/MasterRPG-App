// @copyright André Trettin

import CryptoKit
import Foundation
import Synchronization

// The import diagnostics, limits and errors, split out of FoundryRuleModels.swift. See CODE_AUDIT_29 §9.9.

public struct FoundryImportDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public enum Severity: String, Codable, Equatable, Sendable {
        case information
        case warning
    }

    public var id: String { "\(code):\(packName ?? "package"): \(message)" }

    public let severity: Severity
    public let code: String
    public let message: String
    public let packName: String?

    public init(severity: Severity, code: String, message: String, packName: String? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.packName = packName
    }
}

public struct FoundryImportLimits: Equatable, Sendable {
    public static let `default` = Self()

    /// Decoded rule data (and one batch of resources) the importer keeps in memory. A document
    /// tree takes 5-10 times the size of its JSON, so a limit sized for a Mac gets an iPhone or
    /// an Apple TV killed by jetsam instead of rejecting the file with `fileTooLarge`. The
    /// archive itself is read from disk and keeps its limit. See CODE_AUDIT_26 §7.3.
#if os(macOS)
    public static let platformMemoryLimit = 512 * ByteUnit.mebibyte
#else
    public static let platformMemoryLimit = 128 * ByteUnit.mebibyte
#endif

    public let maximumArchiveSize: Int
    public let maximumEntrySize: Int
    public let maximumRuleDataSize: Int
    public let maximumResourceBatchSize: Int
    public let maximumDocumentCount: Int
    /// Bounds newline-delimited transport records, including tombstones and malformed records.
    public let maximumRecordCount: Int
    /// Bounds warnings created from repeated malformed or forward-versioned records.
    public let maximumDiagnosticCount: Int
    public let maximumUniversalVTTElementCount: Int
    public let maximumUniversalVTTCoordinateMagnitude: Double
    public let maximumUniversalVTTPixelDimension: Double

    public init(
        maximumArchiveSize: Int = ByteUnit.gibibyte,
        maximumEntrySize: Int = 64 * ByteUnit.mebibyte,
        maximumRuleDataSize: Int = FoundryImportLimits.platformMemoryLimit,
        maximumResourceBatchSize: Int = FoundryImportLimits.platformMemoryLimit,
        maximumDocumentCount: Int = 100_000,
        maximumRecordCount: Int = 400_000,
        maximumDiagnosticCount: Int = 1_000,
        maximumUniversalVTTElementCount: Int = 1_000_000,
        maximumUniversalVTTCoordinateMagnitude: Double = 1_000_000,
        maximumUniversalVTTPixelDimension: Double = 1_000_000
    ) {
        self.maximumArchiveSize = maximumArchiveSize
        self.maximumEntrySize = maximumEntrySize
        self.maximumRuleDataSize = maximumRuleDataSize
        self.maximumResourceBatchSize = maximumResourceBatchSize
        self.maximumDocumentCount = maximumDocumentCount
        self.maximumRecordCount = maximumRecordCount
        self.maximumDiagnosticCount = maximumDiagnosticCount
        self.maximumUniversalVTTElementCount = maximumUniversalVTTElementCount
        self.maximumUniversalVTTCoordinateMagnitude = maximumUniversalVTTCoordinateMagnitude
        self.maximumUniversalVTTPixelDimension = maximumUniversalVTTPixelDimension
    }
}

public enum FoundryImportError: Error, Equatable, LocalizedError, Sendable {
    case fileTooLarge(Int)
    case invalidArchive(String)
    case encryptedArchive
    case unsupportedZIPCompression(UInt16)
    case unsupportedLevelDBCompression(UInt8)
    case unsupportedLevelDBLog(String)
    case unsupportedLevelDBTableSet(pack: String, tableCount: Int)
    case corruptLevelDB(String)
    case missingManifest
    case ambiguousManifest
    case invalidManifest(String)
    case invalidDocument(pack: String, key: String)
    case missingPack(String)
    case tooManyDocuments(Int)
    case tooManyUniversalVTTElements(Int)
    case resourceUnavailable(String)
    case duplicateResourceRequest
    case sourceMismatch
    case resourceIntegrityFailure(String)
    case bareManifestRequiresContainer(String)
    case unsupportedSource

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            String(localized: "The Foundry package is too large (\(size) bytes).", bundle: .module)
        case .invalidArchive(let reason):
            String(localized: "The Foundry ZIP archive is invalid: \(reason)", bundle: .module)
        case .encryptedArchive:
            String(localized: "Encrypted ZIP archives are not supported.", bundle: .module)
        case .unsupportedZIPCompression(let method):
            String(localized: "ZIP compression method \(Int(method)) is not supported.", bundle: .module)
        case .unsupportedLevelDBCompression(let method):
            String(localized: "LevelDB compression method \(Int(method)) is not supported.", bundle: .module)
        case .unsupportedLevelDBLog(let path):
            String(localized: "The mutable LevelDB log \(path) contains data that cannot be imported safely. Compact the Foundry pack first.", bundle: .module)
        case .unsupportedLevelDBTableSet(let pack, let tableCount):
            String(localized: "The Foundry compendium \(pack) contains \(tableCount) LevelDB tables. Import currently requires a compacted pack with exactly one table.", bundle: .module)
        case .corruptLevelDB(let reason):
            String(localized: "The Foundry compendium database is corrupt: \(reason)", bundle: .module)
        case .missingManifest:
            String(localized: "The package does not contain a supported Foundry manifest.", bundle: .module)
        case .ambiguousManifest:
            String(localized: "The package contains more than one equally likely Foundry manifest.", bundle: .module)
        case .invalidManifest(let reason):
            String(localized: "The Foundry package manifest is invalid: \(reason)", bundle: .module)
        case .invalidDocument(let pack, let key):
            String(localized: "The Foundry compendium \(pack) contains an invalid document at \(key).", bundle: .module)
        case .missingPack(let name):
            String(localized: "The Foundry compendium \(name) is missing.", bundle: .module)
        case .tooManyDocuments(let count):
            String(localized: "The Foundry package contains too many documents (\(count)).", bundle: .module)
        case .tooManyUniversalVTTElements(let count):
            String(localized: "The Universal VTT map contains too many geometry elements (\(count)).", bundle: .module)
        case .resourceUnavailable(let path):
            String(localized: "The Foundry resource \(path) is not packaged in the selected artifact.", bundle: .module)
        case .duplicateResourceRequest:
            String(localized: "A Foundry resource was requested more than once in the same batch.", bundle: .module)
        case .sourceMismatch:
            String(localized: "The selected Foundry source does not match the package that was inspected.", bundle: .module)
        case .resourceIntegrityFailure(let path):
            String(localized: "The Foundry resource \(path) changed or failed its integrity check.", bundle: .module)
        case .bareManifestRequiresContainer(let filename):
            String(localized: "Select the folder or ZIP package containing \(filename), not the manifest file by itself.", bundle: .module)
        case .unsupportedSource:
            String(localized: "Select a supported Foundry package, document export, database, bridge file, or Universal VTT map.", bundle: .module)
        }
    }
}
