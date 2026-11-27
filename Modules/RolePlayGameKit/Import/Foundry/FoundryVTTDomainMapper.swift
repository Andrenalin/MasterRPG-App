// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import Foundation
import MapRPG
import Observation
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import SwiftUI
import TableRPG
import UniformTypeIdentifiers

enum FoundryImportCategory: String, CaseIterable, Identifiable, Sendable {
    case actors
    case items
    case rules
    case scenes
    case journals
    case tables
    case playlists
    case cards
    case adventures
    case combats
    case chat
    case users
    case macros
    case assets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actors: String(localized: "Actors and characters", bundle: .module)
        case .items: String(localized: "Items and values", bundle: .module)
        case .rules: String(localized: "Rules and system content", bundle: .module)
        case .scenes: String(localized: "Scenes, levels, tokens, and walls", bundle: .module)
        case .journals: String(localized: "Journals", bundle: .module)
        case .tables: String(localized: "Roll tables and dice", bundle: .module)
        case .playlists: String(localized: "Playlists and sounds", bundle: .module)
        case .cards: String(localized: "Cards and decks", bundle: .module)
        case .adventures: String(localized: "Adventures", bundle: .module)
        case .combats: String(localized: "Combats", bundle: .module)
        case .chat: String(localized: "Chat history", bundle: .module)
        case .users: String(localized: "Users and ownership metadata", bundle: .module)
        case .macros: String(localized: "Macros as text", bundle: .module)
        case .assets: String(localized: "Packaged media", bundle: .module)
        }
    }

    static let privacySafeDefaults = Set(Self.allCases.filter { $0 != .chat && $0 != .users })
}

struct FoundryMappedImport: Sendable {
    let batch: ExternalImportBatch
    let mappings: [FoundryImportMapping]
    let archiveId: UUID
    let rawOnlyDocumentCount: Int
    let missingResources: [FoundryPackageResource]
    let unsupportedResources: [FoundryPackageResource]
    let archivePackage: FoundryVTTImportPackage
}

typealias FoundryResourceLoader = @Sendable (FoundryPackageResource) async throws -> Data

/// Conservative bounds for geometry projected into MapRPG. The original numbers always remain
/// available in the Foundry source archive, so an unsafe value is omitted instead of coerced.
enum FoundryProjectionGeometry {
    static let maximumMagnitude = 1_000_000.0

    static func sceneGeometry(in rawData: FoundryJSONValue) -> FoundrySceneProjectionGeometry? {
        guard let width = number(
            rawData["width"],
            defaultValue: 1_200,
            allowedRange: 1...maximumMagnitude
        ), let height = number(
            rawData["height"],
            defaultValue: 800,
            allowedRange: 1...maximumMagnitude
        ), let gridSize = number(
            rawData.value(at: "grid.size"),
            defaultValue: 100,
            allowedRange: 0...maximumMagnitude
        ) else { return nil }
        return FoundrySceneProjectionGeometry(width: width, height: height, gridSize: gridSize)
    }

    static func coordinate(_ value: FoundryJSONValue) -> Double? {
        number(value, allowedRange: -maximumMagnitude...maximumMagnitude)
    }

    static func coordinate(_ value: FoundryJSONValue?, defaultValue: Double) -> Double? {
        number(
            value,
            defaultValue: defaultValue,
            allowedRange: -maximumMagnitude...maximumMagnitude
        )
    }

    static func tokenDimension(_ value: FoundryJSONValue?, defaultValue: Double) -> Double? {
        number(
            value,
            defaultValue: defaultValue,
            allowedRange: Double.leastNonzeroMagnitude...maximumMagnitude
        )
    }

    static func tokenCenter(origin: Double, gridUnits: Double, gridSize: Double) -> Double? {
        let center = origin + gridUnits * gridSize / 2
        guard center.isFinite, abs(center) <= maximumMagnitude else { return nil }
        return center
    }

    static func exactInteger(_ value: FoundryJSONValue?, defaultValue: Int) -> Int? {
        guard let value else { return defaultValue }
        return switch value {
        case .integer(let value): Int(exactly: value)
        case .unsignedInteger(let value): Int(exactly: value)
        case .number(let value) where value.isFinite: Int(exactly: value)
        default: nil
        }
    }

    private static func number(
        _ value: FoundryJSONValue?,
        defaultValue: Double,
        allowedRange: ClosedRange<Double>
    ) -> Double? {
        guard let value else { return defaultValue }
        return number(value, allowedRange: allowedRange)
    }

    private static func number(
        _ value: FoundryJSONValue,
        allowedRange: ClosedRange<Double>
    ) -> Double? {
        let number: Double? = switch value {
        case .integer(let value): Double(value)
        case .unsignedInteger(let value): Double(value)
        case .number(let value): value
        default: nil
        }
        guard let number, number.isFinite, allowedRange.contains(number) else { return nil }
        return number
    }
}

struct FoundrySceneProjectionGeometry: Equatable, Sendable {
    let width: Double
    let height: Double
    let gridSize: Double
}

enum FoundryGeometryWarning: Hashable {
    case scene
    case token
    case wall
    case levelElevation

    var message: String {
        switch self {
        case .scene:
            String(localized: "One or more scenes had invalid or out-of-range dimensions and remain only in the RuleRPG source archive.", bundle: .module)
        case .token:
            String(localized: "One or more tokens had invalid or out-of-range geometry and were omitted from map projections.", bundle: .module)
        case .wall:
            String(localized: "One or more walls had invalid or out-of-range geometry or restriction values and were omitted from map projections.", bundle: .module)
        case .levelElevation:
            String(localized: "One or more level elevations were invalid or out of range and were omitted from map projections.", bundle: .module)
        }
    }
}

@MainActor
struct FoundryVTTDomainMapper {
    func map(
        package: FoundryVTTImportPackage,
        sourceUrl: URL,
        sourceScopeId: UUID,
        selectedCategories: Set<FoundryImportCategory> = FoundryImportCategory.privacySafeDefaults,
        resourceLoader: @escaping FoundryResourceLoader
    ) async throws -> FoundryMappedImport {
        let state = FoundryMappingState(
            package: package,
            sourceUrl: sourceUrl,
            sourceScopeId: sourceScopeId,
            selectedCategories: selectedCategories,
            resourceLoader: resourceLoader
        )
        return try await state.build()
    }
}

@MainActor
final class FoundryMappingState {
    init(
        package: FoundryVTTImportPackage,
        sourceUrl: URL,
        sourceScopeId: UUID,
        selectedCategories: Set<FoundryImportCategory>,
        resourceLoader: @escaping FoundryResourceLoader
    ) {
        self.package = package
        self.sourceUrl = sourceUrl
        self.sourceScopeId = sourceScopeId
        self.selectedCategories = selectedCategories
        self.resourceLoader = resourceLoader
        privacyFilteredPackage = FoundryVTTArchiveSanitizer.sanitize(
            package,
            includingChat: selectedCategories.contains(.chat),
            includingUsers: selectedCategories.contains(.users)
        )
        let fallback = sourceUrl.deletingPathExtension().lastPathComponent
        packageName = FoundryTextDecoder.plainText(fromHTML: package.manifest?.title ?? fallback)
        // Scope identity must survive content edits so repeated imports update the same records.
        // The content hash is integrity metadata, not identity. Including the package kind avoids
        // collisions between, for example, a System and World which happen to share an id.
        packageIdentifier = "\(package.kind.rawValue):\(package.manifest?.id ?? fallback)"
        provenance = ExternalImportProvenance(
            source: "Foundry VTT",
            sourceScopeId: sourceScopeId,
            packageIdentifier: packageIdentifier,
            sourcePath: sourceUrl.lastPathComponent,
            sourceVersion: package.manifest?.version
        )
    }

    let package: FoundryVTTImportPackage
    let privacyFilteredPackage: FoundryVTTImportPackage
    let sourceUrl: URL
    let sourceScopeId: UUID
    let selectedCategories: Set<FoundryImportCategory>
    let resourceLoader: FoundryResourceLoader
    let packageName: String
    let packageIdentifier: String
    let provenance: ExternalImportProvenance

    var items: [ExternalImportBatchItem] = []
    var emittedItems: Set<DestinationKey> = []
    var mappingReferences: [String: Set<FoundryImportMappingReference>] = [:]
    var warnings: [String] = []
    var rawOnlyDocumentIds: Set<String> = []
    var folderIds: [FolderKey: Set<UUID>] = [:]
    var folderAliases: [FolderAliasKey: Set<UUID>] = [:]
    var resourceIds: [ResourceKey: UUID] = [:]
    /// The first resource projected for a key, to tell a repeated call from a path collision.
    var resourceSources: [ResourceKey: FoundryPackageResource] = [:]
    var resourcesByCanonicalPath: [String: FoundryPackageResource] = [:]
    var resourcesByAlias: [String: FoundryPackageResource] = [:]
    var ambiguousResourceCanonicalPaths: Set<String> = []
    var ambiguousResourceAliases: Set<String> = []
    var actorsByDocumentId: [String: UUID] = [:]
    var levelMapIds: [String: UUID] = [:]
    var targetsByFoundryUUID: [String: Destination] = [:]
    var documentTypesById: [String: FoundryDocumentType] = [:]
    var indexedDocuments: [FoundryDocument] = []
    var privacyFilteredDocumentsById: [String: FoundryDocument] = [:]
    var emittedGeometryWarnings = Set<FoundryGeometryWarning>()
    var cooperativeWorkCount = 0
    /// Plain text of the document and rule descriptions, computed off the main actor by
    /// `FoundryTextPrepass` before the models are built. A string that is not in it is converted
    /// on demand.
    var plainTextCache: [String: String] = [:]
    /// The flattened `system` values of the actors and items with their ids, computed off the
    /// main actor by `FoundryValuePrepass`. A value that is not in it is planned on demand.
    var valuePlans: [String: FoundryValuePlan] = [:]
    /// How many units of mapping work run between `Task.yield()` calls in
    /// `cooperativeCheckpoint()`. The model construction runs on the Main Actor (the models are
    /// @MainActor @Observable classes, so it can't move to a background actor without a much
    /// larger rewrite), and the HTML to plain text conversion of the descriptions already ran off
    /// it (`FoundryTextPrepass`). This keeps SwiftUI's render loop and other Main Actor work
    /// interleaved during a large import instead of one long unbroken run.
    /// Lowered from 64 to yield more often, at the cost of slightly more yield overhead.
    private static let cooperativeYieldInterval = 16

    func build() async throws -> FoundryMappedImport {
        try await cooperativeCheckpoint()
        try await indexResources()
        try await cooperativeCheckpoint()
        try await indexDocuments()
        try await cooperativeCheckpoint()
        plainTextCache = await FoundryTextPrepass.plainTexts(of: FoundryTextPrepass.htmlSources(
            documents: allDocuments,
            rulePackage: selectedCategories.contains(.rules) ? privacyFilteredPackage.rulePackage : nil
        ))
        try Task.checkCancellation()
        if selectedCategories.contains(.actors) || selectedCategories.contains(.items) {
            valuePlans = await FoundryValuePrepass.plans(
                of: FoundryValuePrepass.sources(documents: allDocuments),
                scope: sourceScopeId
            )
            try Task.checkCancellation()
        }
        try await createFolders()
        try await cooperativeCheckpoint()
        if selectedCategories.contains(.rules) {
            try await createRuleProjection()
        }
        try await cooperativeCheckpoint()
        if selectedCategories.contains(.assets) {
            try await createPackagedAssets()
        }

        for collection in package.collections {
            try await cooperativeCheckpoint()
            if selectedCategories.contains(.chat) {
                mapChatTranscript(collection)
            }
            for document in collection.documents where document.documentType != .chatMessage {
                try await cooperativeCheckpoint()
                try await mapDocument(document)
            }
        }

        for document in allDocuments where mappingReferences[document.id] == nil
            && document.documentType != .folder
            && retainsRawDocument(document) {
            try await cooperativeCheckpoint()
            rawOnlyDocumentIds.insert(document.id)
        }

        if !selectedCategories.contains(.chat) {
            warnings.append(String(localized: "Chat messages were excluded from both projection and the RuleRPG source archive.", bundle: .module))
        }
        if !selectedCategories.contains(.users) {
            warnings.append(String(localized: "User documents and common ownership identifiers were excluded from the RuleRPG source archive.", bundle: .module))
        }
        warnings.append(contentsOf: package.diagnostics.map(\.message))
        let batch = ExternalImportBatch(
            id: stableId("batch"),
            title: packageName,
            provenance: provenance,
            items: items,
            warnings: Array(Set(warnings)).sorted()
        )
        let mappings = mappingReferences
            .map { FoundryImportMapping(foundryIdentifier: $0.key, references: Array($0.value).sorted(by: mappingOrder)) }
            .sorted { $0.foundryIdentifier < $1.foundryIdentifier }
        let projectedResourcePaths = Set(resourceIds.keys.map(\.path))
        return FoundryMappedImport(
            batch: batch,
            mappings: mappings,
            archiveId: sourceScopeId,
            rawOnlyDocumentCount: rawOnlyDocumentIds.count,
            missingResources: package.resources.filter { $0.location == .unresolved },
            unsupportedResources: package.resources.filter {
                module(for: $0.logicalPath) == nil
                    && !projectedResourcePaths.contains(canonicalResourcePath($0.logicalPath))
            },
            archivePackage: packageForArchive()
        )
    }

    func cooperativeCheckpoint() async throws {
        try Task.checkCancellation()
        cooperativeWorkCount += 1
        if cooperativeWorkCount.isMultiple(of: Self.cooperativeYieldInterval) {
            await Task.yield()
            try Task.checkCancellation()
        }
    }

    /// Chat can contain private, blind, or whispered messages. When the user leaves the Chat
    /// category disabled, remove those documents from the durable RuleRPG source archive as well
    /// as from the display projection.
    func packageForArchive() -> FoundryVTTImportPackage {
        privacyFilteredPackage
    }

    func retainsRawDocument(_ document: FoundryDocument) -> Bool {
        if document.documentType == .chatMessage { return selectedCategories.contains(.chat) }
        if document.documentType == .user { return selectedCategories.contains(.users) }
        return true
    }

}
