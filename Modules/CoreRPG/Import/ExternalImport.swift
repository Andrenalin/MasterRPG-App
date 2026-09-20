// @copyright André Trettin

import Foundation
import Observation
import os.log

// MARK: - Provenance & Attachments

/// Identifies where a staged external item came from without coupling CoreRPG to
/// a particular importer (Foundry, another VTT, or a future interchange format).
public struct ExternalImportProvenance: Hashable, Codable, Sendable {
    public init(
        source: String,
        sourceScopeID: UUID? = nil,
        packageIdentifier: String? = nil,
        documentIdentifier: String? = nil,
        sourcePath: String? = nil,
        sourceVersion: String? = nil
    ) {
        self.source = source
        self.sourceScopeID = sourceScopeID
        self.packageIdentifier = packageIdentifier
        self.documentIdentifier = documentIdentifier
        self.sourcePath = sourcePath
        self.sourceVersion = sourceVersion
    }

    public let source: String
    /// Stable registry identity; mutable hashes and filenames must not be used as item identity.
    public let sourceScopeID: UUID?
    public let packageIdentifier: String?
    public let documentIdentifier: String?
    public let sourcePath: String?
    public let sourceVersion: String?
}

/// Binary data associated with one staged item. The loader is deliberately lazy:
/// staging and review never read or install attachment bytes.
public struct ExternalImportAttachment: Identifiable, Sendable {
    public typealias Loader = @Sendable () async throws -> Data

    public init(
        id: UUID = UUID(),
        fileID: UUID? = nil,
        suggestedFilename: String,
        contentTypeIdentifier: String? = nil,
        expectedByteCount: Int? = nil,
        contentHash: String? = nil,
        load: @escaping Loader
    ) {
        self.id = id
        self.fileID = fileID ?? id
        self.suggestedFilename = suggestedFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.expectedByteCount = expectedByteCount
        self.contentHash = contentHash
        self.loader = load
    }

    public init(
        id: UUID = UUID(),
        fileID: UUID? = nil,
        suggestedFilename: String,
        contentTypeIdentifier: String? = nil,
        data: Data
    ) {
        let hash = FileUrl.contentHash(of: data)
        self.init(
            id: id,
            fileID: fileID,
            suggestedFilename: suggestedFilename,
            contentTypeIdentifier: contentTypeIdentifier,
            expectedByteCount: data.count,
            contentHash: hash,
            load: { data }
        )
    }

    public let id: UUID
    public let fileID: UUID
    public let suggestedFilename: String
    public let contentTypeIdentifier: String?
    public let expectedByteCount: Int?
    /// Base-64 encoded SHA-256, matching `FileUrl.contentHash`.
    public let contentHash: String?

    private let loader: Loader

    public func load() async throws -> Data {
        try await loader()
    }
}

// MARK: - Batch Items

/// One fully converted domain model waiting for review. Creating this value must
/// not insert the model or write its optional attachment.
public struct ExternalImportBatchItem: Identifiable, Sendable {
    @MainActor
    public init<Model>(
        id: UUID,
        module: NetworkModules,
        name: String,
        model: Model,
        provenance: ExternalImportProvenance,
        attachment: ExternalImportAttachment? = nil,
        decisionOwnerID: UUID? = nil,
        warnings: [String] = []
    ) where Model: ItemDataAccessable & Observable {
        self.id = id
        self.module = module
        self.name = name
        self.model = model
        self.modelID = model.id
        self.modelModule = Model.typeId
        self.provenance = provenance
        self.attachment = attachment
        self.decisionOwnerID = decisionOwnerID
        self.warnings = warnings
        self.modelCopier = { candidate in
            guard let candidate = candidate as? Model else { return nil }
            return candidate.copy()
        }
        self.fileUrlReader = { candidate in
            (candidate as? Model)?.fileUrl
        }
        self.fileUrlWriter = { candidate, fileUrl in
            guard var candidate = candidate as? Model else { return nil }
            candidate.fileUrl = fileUrl
            return candidate
        }
    }

    public let id: UUID
    public let module: NetworkModules
    public let name: String
    public let model: any ModelType
    public let modelID: UUID
    public let modelModule: NetworkModules
    public let provenance: ExternalImportProvenance
    public let attachment: ExternalImportAttachment?
    /// An auxiliary item follows its same-module owner's review decision and is not presented as
    /// an independently selectable row. This keeps recursive imported models atomic.
    public let decisionOwnerID: UUID?
    public let warnings: [String]

    public var isAuxiliary: Bool { decisionOwnerID != nil }

    private let modelCopier: @MainActor @Sendable (any ModelType) -> (any ModelType)?
    private let fileUrlReader: @MainActor @Sendable (any ModelType) -> FileUrl?
    private let fileUrlWriter: @MainActor @Sendable (any ModelType, FileUrl) -> (any ModelType)?

    @MainActor
    func copy(_ candidate: any ModelType) -> (any ModelType)? {
        modelCopier(candidate)
    }

    @MainActor
    func fileUrl(from candidate: (any ModelType)?) -> FileUrl? {
        guard let candidate else { return nil }
        return fileUrlReader(candidate)
    }

    @MainActor
    func attaching(_ fileUrl: FileUrl, to candidate: any ModelType) -> (any ModelType)? {
        fileUrlWriter(candidate, fileUrl)
    }
}

/// A partial, additive external import. Absence from this batch never means that
/// a local model should be deleted.
public struct ExternalImportBatch: Identifiable, Sendable {
    public init(
        id: UUID = UUID(),
        title: String,
        provenance: ExternalImportProvenance,
        items: [ExternalImportBatchItem],
        warnings: [String] = []
    ) {
        self.id = id
        self.title = title
        self.provenance = provenance
        self.items = items
        self.warnings = warnings
    }

    public let id: UUID
    public let title: String
    public let provenance: ExternalImportProvenance
    public let items: [ExternalImportBatchItem]
    public let warnings: [String]

    /// External imports intentionally have partial scope. The commit API has no
    /// deletion decision and does not compare this list with the local library.
    public var isPartial: Bool { true }
}

// MARK: - Decisions & Status

public enum ExternalImportDecision: String, CaseIterable, Hashable, Codable, Sendable {
    case skip
    case merge
    case replace
}

public enum ExternalImportConflictStatus: String, Equatable, Sendable {
    case new
    case unchanged
    case changed
}

public enum ExternalImportPhase: Equatable, Sendable {
    case reviewing
    case committing
    case repairing
    case saving
    case rollingBack
    case completed
    case failed
    case cancelled
}

// MARK: - Results & Errors

public struct ExternalImportResult: Equatable, Sendable {
    public init(
        insertedItemCount: Int,
        mergedItemCount: Int,
        replacedItemCount: Int,
        unchangedItemCount: Int,
        skippedItemCount: Int,
        installedAttachmentCount: Int,
        reusedAttachmentCount: Int,
        importedItemIDs: [NetworkModules: Set<UUID>]
    ) {
        self.insertedItemCount = insertedItemCount
        self.mergedItemCount = mergedItemCount
        self.replacedItemCount = replacedItemCount
        self.unchangedItemCount = unchangedItemCount
        self.skippedItemCount = skippedItemCount
        self.installedAttachmentCount = installedAttachmentCount
        self.reusedAttachmentCount = reusedAttachmentCount
        self.importedItemIDs = importedItemIDs
    }

    public let insertedItemCount: Int
    public let mergedItemCount: Int
    public let replacedItemCount: Int
    public let unchangedItemCount: Int
    public let skippedItemCount: Int
    public let installedAttachmentCount: Int
    public let reusedAttachmentCount: Int
    public let importedItemIDs: [NetworkModules: Set<UUID>]
}

public enum ExternalImportError: LocalizedError, Equatable, Sendable {
    case commitAlreadyRunning
    case commitAlreadyCompleted
    case duplicateItem(itemId: UUID, module: NetworkModules)
    case unsupportedModule(NetworkModules)
    case incompatibleModel(itemId: UUID, module: NetworkModules)
    case missingFileController(itemId: UUID, module: NetworkModules)
    case attachmentSizeMismatch(attachmentID: UUID, expected: Int, actual: Int)
    case attachmentHashMismatch(attachmentID: UUID)
    case attachmentInstallFailed(attachmentID: UUID)
    case duplicateAttachmentFileID(UUID)
    case rollbackIncomplete(originalError: String, rollbackErrors: [String])

    public var errorDescription: String? {
        switch self {
        case .commitAlreadyRunning:
            "An external import is already running."
        case .commitAlreadyCompleted:
            "This external import has already completed."
        case .duplicateItem(let itemId, let module):
            "Item \(itemId.uuidString) occurs more than once in the \(module.title) import batch."
        case .unsupportedModule(let module):
            "The \(module.title) module cannot receive this import."
        case .incompatibleModel(let itemId, let module):
            "Item \(itemId.uuidString) is not compatible with the \(module.title) module."
        case .missingFileController(let itemId, let module):
            "Item \(itemId.uuidString) has an attachment, but \(module.title) cannot store files."
        case .attachmentSizeMismatch(_, let expected, let actual):
            "Attachment size mismatch: expected \(expected) bytes but loaded \(actual)."
        case .attachmentHashMismatch:
            "Attachment integrity validation failed."
        case .attachmentInstallFailed:
            "The attachment could not be installed."
        case .duplicateAttachmentFileID(let fileID):
            "More than one selected attachment uses file id \(fileID.uuidString)."
        case .rollbackIncomplete(let originalError, let rollbackErrors):
            "The import failed (\(originalError)), and rollback was incomplete: \(rollbackErrors.joined(separator: "; "))"
        }
    }
}
