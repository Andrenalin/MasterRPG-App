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
        case .actors: "Actors and characters"
        case .items: "Items and values"
        case .rules: "Rules and system content"
        case .scenes: "Scenes, levels, tokens, and walls"
        case .journals: "Journals"
        case .tables: "Roll tables and dice"
        case .playlists: "Playlists and sounds"
        case .cards: "Cards and decks"
        case .adventures: "Adventures"
        case .combats: "Combats"
        case .chat: "Chat history"
        case .users: "Users and ownership metadata"
        case .macros: "Macros as text"
        case .assets: "Packaged media"
        }
    }

    static let privacySafeDefaults = Set(Self.allCases.filter { $0 != .chat && $0 != .users })
}

struct FoundryMappedImport: Sendable {
    let batch: ExternalImportBatch
    let mappings: [FoundryImportMapping]
    let archiveID: UUID
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

private enum FoundryGeometryWarning: Hashable {
    case scene
    case token
    case wall
    case levelElevation

    var message: String {
        switch self {
        case .scene:
            "One or more scenes had invalid or out-of-range dimensions and remain only in the RuleRPG source archive."
        case .token:
            "One or more tokens had invalid or out-of-range geometry and were omitted from map projections."
        case .wall:
            "One or more walls had invalid or out-of-range geometry or restriction values and were omitted from map projections."
        case .levelElevation:
            "One or more level elevations were invalid or out of range and were omitted from map projections."
        }
    }
}

@MainActor
struct FoundryVTTDomainMapper {
    func map(
        package: FoundryVTTImportPackage,
        sourceURL: URL,
        sourceScopeID: UUID,
        selectedCategories: Set<FoundryImportCategory> = FoundryImportCategory.privacySafeDefaults,
        resourceLoader: @escaping FoundryResourceLoader
    ) async throws -> FoundryMappedImport {
        let state = FoundryMappingState(
            package: package,
            sourceURL: sourceURL,
            sourceScopeID: sourceScopeID,
            selectedCategories: selectedCategories,
            resourceLoader: resourceLoader
        )
        return try await state.build()
    }
}

@MainActor
private final class FoundryMappingState {
    init(
        package: FoundryVTTImportPackage,
        sourceURL: URL,
        sourceScopeID: UUID,
        selectedCategories: Set<FoundryImportCategory>,
        resourceLoader: @escaping FoundryResourceLoader
    ) {
        self.package = package
        self.sourceURL = sourceURL
        self.sourceScopeID = sourceScopeID
        self.selectedCategories = selectedCategories
        self.resourceLoader = resourceLoader
        privacyFilteredPackage = FoundryVTTArchiveSanitizer.sanitize(
            package,
            includingChat: selectedCategories.contains(.chat),
            includingUsers: selectedCategories.contains(.users)
        )
        let fallback = sourceURL.deletingPathExtension().lastPathComponent
        packageName = FoundryTextDecoder.plainText(fromHTML: package.manifest?.title ?? fallback)
        // Scope identity must survive content edits so repeated imports update the same records.
        // The content hash is integrity metadata, not identity. Including the package kind avoids
        // collisions between, for example, a System and World which happen to share an id.
        packageIdentifier = "\(package.kind.rawValue):\(package.manifest?.id ?? fallback)"
        provenance = ExternalImportProvenance(
            source: "Foundry VTT",
            sourceScopeID: sourceScopeID,
            packageIdentifier: packageIdentifier,
            sourcePath: sourceURL.lastPathComponent,
            sourceVersion: package.manifest?.version
        )
    }

    let package: FoundryVTTImportPackage
    let privacyFilteredPackage: FoundryVTTImportPackage
    let sourceURL: URL
    let sourceScopeID: UUID
    let selectedCategories: Set<FoundryImportCategory>
    let resourceLoader: FoundryResourceLoader
    let packageName: String
    let packageIdentifier: String
    let provenance: ExternalImportProvenance

    var items: [ExternalImportBatchItem] = []
    var emittedItems: Set<DestinationKey> = []
    var mappingReferences: [String: Set<FoundryImportMappingReference>] = [:]
    var warnings: [String] = []
    var rawOnlyDocumentIDs: Set<String> = []
    var folderIDs: [FolderKey: Set<UUID>] = [:]
    var folderAliases: [FolderAliasKey: Set<UUID>] = [:]
    var resourceIDs: [ResourceKey: UUID] = [:]
    var resourcesByCanonicalPath: [String: FoundryPackageResource] = [:]
    var resourcesByAlias: [String: FoundryPackageResource] = [:]
    var ambiguousResourceCanonicalPaths: Set<String> = []
    var ambiguousResourceAliases: Set<String> = []
    var actorsByDocumentID: [String: UUID] = [:]
    var levelMapIDs: [String: UUID] = [:]
    var targetsByFoundryUUID: [String: Destination] = [:]
    var documentTypesByID: [String: FoundryDocumentType] = [:]
    var indexedDocuments: [FoundryDocument] = []
    var privacyFilteredDocumentsByID: [String: FoundryDocument] = [:]
    var emittedGeometryWarnings = Set<FoundryGeometryWarning>()
    var cooperativeWorkCount = 0

    func build() async throws -> FoundryMappedImport {
        try await cooperativeCheckpoint()
        try await indexResources()
        try await cooperativeCheckpoint()
        try await indexDocuments()
        try await cooperativeCheckpoint()
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
                mapDocument(document)
            }
        }

        for document in allDocuments where mappingReferences[document.id] == nil
            && document.documentType != .folder
            && retainsRawDocument(document) {
            try await cooperativeCheckpoint()
            rawOnlyDocumentIDs.insert(document.id)
        }

        if !selectedCategories.contains(.chat) {
            warnings.append("Chat messages were excluded from both projection and the RuleRPG source archive.")
        }
        if !selectedCategories.contains(.users) {
            warnings.append("User documents and common ownership identifiers were excluded from the RuleRPG source archive.")
        }
        warnings.append(contentsOf: package.diagnostics.map(\.message))
        let batch = ExternalImportBatch(
            id: stableID("batch"),
            title: packageName,
            provenance: provenance,
            items: items,
            warnings: Array(Set(warnings)).sorted()
        )
        let mappings = mappingReferences
            .map { FoundryImportMapping(foundryIdentifier: $0.key, references: Array($0.value).sorted(by: mappingOrder)) }
            .sorted { $0.foundryIdentifier < $1.foundryIdentifier }
        let projectedResourcePaths = Set(resourceIDs.keys.map(\.path))
        return FoundryMappedImport(
            batch: batch,
            mappings: mappings,
            archiveID: sourceScopeID,
            rawOnlyDocumentCount: rawOnlyDocumentIDs.count,
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
        if cooperativeWorkCount.isMultiple(of: 64) {
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

// MARK: - Indexes and folders

private extension FoundryMappingState {
    func indexResources() async throws {
        var canonicalCandidates: [String: Set<FoundryPackageResource>] = [:]
        var aliasCandidates: [String: Set<FoundryPackageResource>] = [:]
        for resource in package.resources {
            try await cooperativeCheckpoint()
            let canonicalPath = canonicalResourcePath(resource.logicalPath)
            canonicalCandidates[canonicalPath, default: []].insert(resource)
            for path in [resource.logicalPath, resource.packagePath].compactMap({ $0 }) {
                aliasCandidates[resourceAlias(path), default: []].insert(resource)
            }
        }
        for (path, candidates) in canonicalCandidates {
            try await cooperativeCheckpoint()
            if candidates.count == 1, let resource = candidates.first {
                resourcesByCanonicalPath[path] = resource
            } else {
                ambiguousResourceCanonicalPaths.insert(path)
                warnings.append("Packaged resource path \(path) is duplicated and will not be attached automatically.")
            }
        }
        for (alias, candidates) in aliasCandidates {
            try await cooperativeCheckpoint()
            if candidates.count == 1, let resource = candidates.first {
                resourcesByAlias[alias] = resource
            } else {
                ambiguousResourceAliases.insert(alias)
                warnings.append("Packaged resource alias \(alias) matches multiple files and will not be attached automatically.")
            }
        }
    }

    func indexDocuments() async throws {
        indexedDocuments = try await collectDocumentsForIndexing()
        for document in privacyFilteredPackage.allDocuments {
            try await cooperativeCheckpoint()
            privacyFilteredDocumentsByID[document.id] = document
        }
        for document in indexedDocuments {
            try await cooperativeCheckpoint()
            documentTypesByID[document.id] = document.documentType
        }
        for scene in indexedDocuments where scene.documentType == .scene {
            try await cooperativeCheckpoint()
            let levels = scene.embeddedDocuments.filter { $0.documentType == .level }
            guard !levels.isEmpty else { continue }
            let initialDocumentID = initialLevel(in: scene, levels: levels).documentID
            for level in levels {
                try await cooperativeCheckpoint()
                levelMapIDs[level.id] = level.documentID == initialDocumentID
                    ? stableID("\(scene.id)#map")
                    : stableID("\(level.id)#level-map")
            }
        }
        var actorCandidates: [String: Set<UUID>] = [:]
        var destinationCandidates: [String: Set<Destination>] = [:]
        for document in indexedDocuments {
            try await cooperativeCheckpoint()
            if document.documentType == .actor, selectedCategories.contains(.actors) {
                actorCandidates[document.documentID, default: []].insert(
                    stableID("\(document.id)#character")
                )
            }
            guard let destination = predictedDestination(for: document) else { continue }
            destinationCandidates[document.id, default: []].insert(destination)
            destinationCandidates[document.documentID, default: []].insert(destination)
            destinationCandidates["\(document.documentType.rawValue).\(document.documentID)", default: []]
                .insert(destination)
            if let sourceUUID = document.sourceUUID {
                for alias in foundryReferenceAliases(for: sourceUUID) {
                    destinationCandidates[alias, default: []].insert(destination)
                }
            }
            if let uuid = document.rawData["uuid"]?.stringValue {
                for alias in foundryReferenceAliases(for: uuid) {
                    destinationCandidates[alias, default: []].insert(destination)
                }
            }
            if let source = document.rawData.value(at: "_stats.compendiumSource")?.stringValue {
                for alias in foundryReferenceAliases(for: source) {
                    destinationCandidates[alias, default: []].insert(destination)
                }
            }
        }
        if selectedCategories.contains(.rules), let rulePackage = privacyFilteredPackage.rulePackage {
            for compendium in rulePackage.compendiums {
                try await cooperativeCheckpoint()
                for rule in compendium.rules {
                    try await cooperativeCheckpoint()
                    let destination = Destination(
                        module: .rule,
                        itemID: stableID("rule#\(rule.id)")
                    )
                    for alias in foundryRuleAliases(
                        rule,
                        systemID: rulePackage.manifest.id
                    ) {
                        destinationCandidates[alias, default: []].insert(destination)
                    }
                }
            }
        }
        for (documentID, candidates) in actorCandidates {
            try await cooperativeCheckpoint()
            if candidates.count == 1, let destination = candidates.first {
                actorsByDocumentID[documentID] = destination
            } else {
                warnings.append("Actor id \(documentID) is ambiguous across Foundry collections; bare token links to it remain unresolved.")
            }
        }
        for (alias, candidates) in destinationCandidates {
            try await cooperativeCheckpoint()
            if candidates.count == 1, let destination = candidates.first {
                targetsByFoundryUUID[alias] = destination
            } else {
                warnings.append("Foundry reference \(alias) is ambiguous across collections and remains unresolved.")
            }
        }
    }

    var allDocuments: [FoundryDocument] {
        if !indexedDocuments.isEmpty { return indexedDocuments }
        return package.collections.flatMap { documentTree($0.documents) }
    }

    func documentTree(_ documents: [FoundryDocument]) -> [FoundryDocument] {
        documents.flatMap { [$0] + documentTree($0.embeddedDocuments) }
    }

    func collectDocumentsForIndexing() async throws -> [FoundryDocument] {
        var result: [FoundryDocument] = []
        var stack = Array(package.collections.flatMap(\.documents).reversed())
        while let document = stack.popLast() {
            try await cooperativeCheckpoint()
            result.append(document)
            stack.append(contentsOf: document.embeddedDocuments.reversed())
        }
        return result
    }

    func createFolders() async throws {
        let declarations = try await makeFolderDeclarations()
        for folder in declarations {
            try await cooperativeCheckpoint()
            for module in modules(for: folder.documentType) {
                let id = stableID(
                    "\(folder.id)#folder#\(module.token)"
                )
                folderIDs[
                    FolderKey(
                        module: module,
                        documentType: folder.documentType,
                        scope: folder.scope,
                        foundryID: folder.documentID
                    ),
                    default: []
                ].insert(id)
                folderAliases[
                    FolderAliasKey(
                        module: module,
                        documentType: folder.documentType,
                        foundryID: folder.documentID
                    ),
                    default: []
                ].insert(id)
            }
        }
        for folder in declarations {
            try await cooperativeCheckpoint()
            for module in modules(for: folder.documentType) {
                guard let id = resolveFolder(
                    module: module,
                    documentType: folder.documentType,
                    scope: folder.scope,
                    foundryID: folder.documentID
                ) else { continue }
                let parentID = folder.parentID.flatMap {
                    resolveFolder(
                        module: module,
                        documentType: folder.documentType,
                        scope: folder.scope,
                        foundryID: $0
                    )
                }
                addFolder(id: id, module: module, name: folder.name, parentID: parentID, sourceID: folder.id)
            }
        }

        for (key, candidates) in folderAliases where candidates.count > 1 {
            warnings.append(
                "Foundry folder id \(key.foundryID) is ambiguous across collections for \(key.module.token); only canonical in-collection links were resolved."
            )
        }
    }

    func makeFolderDeclarations() async throws -> [FolderDeclaration] {
        var declarations: [FolderDeclaration] = []
        for collection in package.collections {
            try await cooperativeCheckpoint()
            declarations.append(contentsOf: collection.folders.map { folder in
                FolderDeclaration(
                    id: folder.id,
                    documentID: folder.documentID,
                    name: folder.name,
                    parentID: folder.parentID,
                    documentType: folder.documentType,
                    scope: canonicalScope(of: folder.id, fallback: collection.id)
                )
            })
            var pendingDocuments = Array(collection.documents.reversed())
            while let document = pendingDocuments.popLast() {
                try await cooperativeCheckpoint()
                pendingDocuments.append(contentsOf: document.embeddedDocuments.reversed())
                guard document.documentType == .folder else { continue }
                declarations.append(FolderDeclaration(
                    id: document.id,
                    documentID: document.documentID,
                    name: document.name,
                    parentID: rawIdentifier(document.rawData["folder"])
                        ?? rawIdentifier(document.rawData["parent"]),
                    documentType: folderContainedDocumentType(document.rawData),
                    scope: canonicalScope(of: document.id, fallback: collection.id)
                ))
            }
        }
        return declarations
    }

    func resolveFolder(
        module: NetworkModules,
        documentType: FoundryDocumentType,
        scope: String,
        foundryID: String
    ) -> UUID? {
        let scoped = folderIDs[
            FolderKey(
                module: module,
                documentType: documentType,
                scope: scope,
                foundryID: foundryID
            )
        ] ?? []
        if scoped.count == 1 { return scoped.first }
        guard scoped.isEmpty else { return nil }
        let aliases = folderAliases[
            FolderAliasKey(module: module, documentType: documentType, foundryID: foundryID)
        ] ?? []
        return aliases.count == 1 ? aliases.first : nil
    }

    func canonicalScope(of canonicalID: String, fallback: String) -> String {
        guard let documentSeparator = canonicalID.lastIndex(of: "/") else { return fallback }
        let withoutDocument = canonicalID[..<documentSeparator]
        guard let typeSeparator = withoutDocument.lastIndex(of: "/") else { return fallback }
        return String(withoutDocument[..<typeSeparator])
    }

    func rawIdentifier(_ value: FoundryJSONValue?) -> String? {
        value?.stringValue ?? value?["_id"]?.stringValue ?? value?["id"]?.stringValue
    }

    func folderContainedDocumentType(_ rawData: FoundryJSONValue) -> FoundryDocumentType {
        let value = rawData["type"]?.stringValue
            ?? rawData["documentType"]?.stringValue
            ?? rawData["documentName"]?.stringValue
        let key = value?.lowercased().filter { $0.isLetter || $0.isNumber }
        return switch key {
        case "actor", "actors": .actor
        case "item", "items": .item
        case "scene", "scenes": .scene
        case "journal", "journals", "journalentry", "journalentries": .journalEntry
        case "rolltable", "rolltables", "table", "tables": .rollTable
        case "playlist", "playlists": .playlist
        case "cards": .cards
        case "adventure", "adventures": .adventure
        case "combat", "combats": .combat
        case "macro", "macros": .macro
        default: .unknown
        }
    }

    func addFolder(id: UUID, module: NetworkModules, name: String, parentID: UUID?, sourceID: String) {
        switch module {
        case .adventure:
            let model = AdventureModel.empty(id)
            configureFolder(model, name: name, parentID: parentID)
            add(model, module: module, sourceID: sourceID)
        case .audio:
            let model = AudioModel.empty(id)
            configureFolder(model, name: name, parentID: parentID)
            add(model, module: module, sourceID: sourceID)
        case .dice:
            let model = DiceModel(id: id, name: name, category: .folder, dice: [], parentId: parentID)
            add(model, module: module, sourceID: sourceID)
        case .map:
            let model = MapModel(id: id, name: name, category: .folder, parentId: parentID)
            add(model, module: module, sourceID: sourceID)
        case .pdf:
            let model = PdfModel.empty(id)
            configureFolder(model, name: name, parentID: parentID)
            add(model, module: module, sourceID: sourceID)
        case .photo:
            let model = PhotoModel.empty(id)
            configureFolder(model, name: name, parentID: parentID)
            add(model, module: module, sourceID: sourceID)
        case .rule:
            let model = RuleModel.empty(id)
            configureFolder(model, name: name, parentID: parentID)
            add(model, module: module, sourceID: sourceID)
        case .space:
            let model = SpaceModel.empty(id)
            configureFolder(model, name: name, parentID: parentID)
            add(model, module: module, sourceID: sourceID)
        case .table:
            let model = TableModel.empty(id)
            configureFolder(model, name: name, parentID: parentID)
            add(model, module: module, sourceID: sourceID)
        case .value:
            let model = ValueModel(id: id, name: name, category: .folder, parentId: parentID)
            add(model, module: module, sourceID: sourceID)
        default:
            break
        }
    }

    func configureFolder<Model: AnyObject & ItemDataAccessable>(_ model: Model, name: String, parentID: UUID?) {
        var model = model
        model.name = name
        model.category = .folder
        model.parentId = parentID
    }
}

// MARK: - Rules

private extension FoundryMappingState {
    /// Projects a normalized Foundry system package into an editable RuleRPG hierarchy while the
    /// complete normalized package continues to live in the source archive.
    func createRuleProjection() async throws {
        guard let rulePackage = privacyFilteredPackage.rulePackage else { return }

        let systemFolderID = stableID("rules#system#\(rulePackage.manifest.id)")
        addFolder(
            id: systemFolderID,
            module: .rule,
            name: rulePackage.manifest.title,
            parentID: nil,
            sourceID: "rules:system:\(rulePackage.manifest.id)"
        )

        for compendium in rulePackage.compendiums {
            try await cooperativeCheckpoint()
            let packName = compendium.manifest.name
            let packFolderID = stableID("rules#pack#\(packName)")
            addFolder(
                id: packFolderID,
                module: .rule,
                name: compendium.manifest.label,
                parentID: systemFolderID,
                sourceID: "rules:pack:\(packName)"
            )

            var foldersByID: [String: FoundryFolder] = [:]
            var projectedFolderIDs: [String: UUID] = [:]
            for folder in compendium.folders {
                try await cooperativeCheckpoint()
                guard foldersByID[folder.id] == nil else {
                    warnings.append("Rule compendium \(packName) contains duplicate folder id \(folder.id); the first folder was retained.")
                    continue
                }
                foldersByID[folder.id] = folder
                projectedFolderIDs[folder.id] = stableID(
                    "rules#pack#\(packName)#folder#\(folder.id)"
                )
            }

            for folder in compendium.folders where foldersByID[folder.id] == folder {
                try await cooperativeCheckpoint()
                guard let folderID = projectedFolderIDs[folder.id] else { continue }
                let parentID = safeRuleFolderParent(
                    for: folder,
                    foldersByID: foldersByID,
                    projectedFolderIDs: projectedFolderIDs,
                    fallback: packFolderID,
                    packName: packName
                )
                addFolder(
                    id: folderID,
                    module: .rule,
                    name: folder.name,
                    parentID: parentID,
                    sourceID: "rules:pack:\(packName):folder:\(folder.id)"
                )
            }

            for rule in compendium.rules {
                try await cooperativeCheckpoint()
                let parentID: UUID
                if let foundryFolderID = rule.folderID,
                   let projectedFolderID = projectedFolderIDs[foundryFolderID] {
                    parentID = projectedFolderID
                } else {
                    parentID = packFolderID
                    if let missingFolderID = rule.folderID, !missingFolderID.isEmpty {
                        warnings.append("Rule \(rule.name) references missing folder \(missingFolderID) in \(packName); it was placed at the compendium root.")
                    }
                }
                let scopedRuleID = stableID("rule#\(rule.id)")
                let identityNamespace = "external-source:\(sourceScopeID.uuidString.lowercased())#rule#\(rule.id)"
                let model = RuleModel.foundry(
                    rule,
                    manifest: rulePackage.manifest,
                    id: scopedRuleID,
                    identityNamespace: identityNamespace,
                    parentId: parentID
                )
                prepareRuleProjection(model, from: rule)
                add(model, module: .rule, sourceID: rule.id)
                recordRuleAliases(
                    rule,
                    systemID: rulePackage.manifest.id,
                    itemID: scopedRuleID
                )
            }
        }
    }

    func safeRuleFolderParent(
        for folder: FoundryFolder,
        foldersByID: [String: FoundryFolder],
        projectedFolderIDs: [String: UUID],
        fallback: UUID,
        packName: String
    ) -> UUID {
        guard let parentFoundryID = folder.parentID, !parentFoundryID.isEmpty else {
            return fallback
        }
        guard projectedFolderIDs[parentFoundryID] != nil else {
            warnings.append("Rule folder \(folder.name) references missing parent \(parentFoundryID) in \(packName); it was placed at the compendium root.")
            return fallback
        }

        var visited = Set([folder.id])
        var candidate: String? = parentFoundryID
        while let current = candidate {
            guard visited.insert(current).inserted else {
                warnings.append("Rule folder hierarchy in \(packName) contains a cycle at \(folder.name); it was placed at the compendium root.")
                return fallback
            }
            candidate = foldersByID[current]?.parentID
        }
        return projectedFolderIDs[parentFoundryID] ?? fallback
    }

    func recordRuleAliases(_ rule: FoundryRuleDefinition, systemID: String, itemID: UUID) {
        for alias in foundryRuleAliases(rule, systemID: systemID) {
            recordMapping(sourceID: alias, module: .rule, itemID: itemID)
        }
    }

    /// Foundry has used both `system.pack.id` compendium references and fully-qualified UUIDs
    /// containing the document type. Keep the aliases already emitted by earlier imports while
    /// also recognizing both canonical link shapes.
    func foundryRuleAliases(_ rule: FoundryRuleDefinition, systemID: String) -> Set<String> {
        let identifiers = Set([
            rule.id,
            rule.documentID,
            "\(rule.packName).\(rule.documentID)",
            "\(systemID).\(rule.packName).\(rule.documentID)",
            "Compendium.\(systemID).\(rule.id)",
            "Compendium.\(systemID).\(rule.packName).\(rule.documentID)",
            "Compendium.\(systemID).\(rule.packName).\(rule.documentType).\(rule.documentID)",
        ])
        return identifiers.reduce(into: Set<String>()) { aliases, identifier in
            aliases.formUnion(foundryReferenceAliases(for: identifier))
        }
    }

    /// The RuleRPG factories deliberately know nothing about mapper-local destinations. Apply the
    /// same text boundary used by every other projection only after all Foundry aliases are indexed.
    /// The normalized source payload is intentionally left untouched here.
    func prepareRuleProjection(_ model: RuleModel, from rule: FoundryRuleDefinition) {
        model.description = safeText(rule.descriptionHTML)

        var referenceIndex = 0
        var embeddedRuleIndex = 0
        var effectIndex = 0
        model.entries = model.entries.map { entry in
            var updated = entry
            switch entry.kind {
            case .reference:
                if rule.references.indices.contains(referenceIndex) {
                    let reference = rule.references[referenceIndex]
                    updated.name = sanitizedFoundryText(
                        reference.label?.isEmpty == false ? reference.label : reference.target
                    )
                    updated.content = projectedRuleReferenceContent(reference)
                } else {
                    updated.content = safeText(entry.content)
                }
                referenceIndex += 1
            case .embeddedRule:
                if rule.embeddedRules.indices.contains(embeddedRuleIndex) {
                    let embeddedRule = rule.embeddedRules[embeddedRuleIndex]
                    updated.name = sanitizedFoundryText(embeddedRule.name)
                    updated.content = projectedEmbeddedRuleContent(embeddedRule)
                } else {
                    updated.content = safeText(entry.content)
                }
                embeddedRuleIndex += 1
            case .effect:
                if rule.effects.indices.contains(effectIndex) {
                    let effect = rule.effects[effectIndex]
                    let fallbackName = "Effect \(effectIndex + 1)"
                    updated.name = sanitizedFoundryText(
                        effect.name.isEmpty ? fallbackName : effect.name
                    )
                    updated.content = projectedRuleEffectContent(effect)
                } else {
                    updated.content = safeText(entry.content)
                }
                effectIndex += 1
            case .value:
                updated.content = decodedFoundryText(entry.content)
            default:
                updated.content = safeText(entry.content)
            }
            return updated
        }
    }

    func projectedRuleReferenceContent(_ reference: FoundryRuleReference) -> String {
        let sanitizedToken = sanitizedFoundryText(reference.rawToken)
        let rewrittenToken = rewriteFoundryLinks(sanitizedToken)
        let target: String
        if rewrittenToken != sanitizedToken {
            target = rewrittenToken
        } else if let destination = destination(for: reference) {
            let label = sanitizedFoundryText(
                reference.label?.isEmpty == false ? reference.label : reference.target
            )
            target = markdownLink(
                name: label,
                module: destination.module,
                itemID: destination.itemID
            )
        } else {
            target = sanitizedFoundryText(reference.target)
        }

        var details = "**Target:** \(target)"
        if let packName = reference.packName, !packName.isEmpty {
            details += "\n\n**Pack:** \(sanitizedFoundryText(packName))"
        }
        if let documentID = reference.documentID, !documentID.isEmpty {
            details += "\n\n**Document:** \(sanitizedFoundryText(documentID))"
        }
        details += "\n\n**Type:** \(sanitizedFoundryText(reference.kind.rawValue))"
        if !reference.sourcePath.isEmpty {
            details += "\n\n**Source:** \(sanitizedFoundryText(reference.sourcePath))"
        }
        return details
    }

    func destination(for reference: FoundryRuleReference) -> Destination? {
        var identifiers = [reference.target]
        if reference.kind == .compendium, !reference.target.hasPrefix("Compendium.") {
            identifiers.append("Compendium.\(reference.target)")
        }
        for identifier in identifiers {
            if let destination = targetsByFoundryUUID[identifier] {
                return destination
            }
            for alias in foundryReferenceAliases(for: identifier) {
                if let destination = targetsByFoundryUUID[alias] {
                    return destination
                }
            }
        }
        return nil
    }

    func projectedEmbeddedRuleContent(_ rule: FoundryEmbeddedRule) -> String {
        var sections = [safeText(rule.descriptionHTML)].filter { !$0.isEmpty }
        let values = rule.values.map { value in
            let path = sanitizedFoundryText(value.path)
            let presentation = presentedFoundryValue(value.value)
            return "- **\(path):** \(presentation)"
        }
        if !values.isEmpty {
            sections.append("**Values**\n\(values.joined(separator: "\n"))")
        }
        if !rule.references.isEmpty {
            let references = rule.references.enumerated().map { index, reference in
                let label = sanitizedFoundryText(
                    reference.label?.isEmpty == false ? reference.label : reference.target
                )
                return "**Reference \(index + 1): \(label)**\n\(projectedRuleReferenceContent(reference))"
            }
            sections.append("**References**\n\n\(references.joined(separator: "\n\n"))")
        }
        if !rule.effects.isEmpty {
            let effects = rule.effects.enumerated().map { index, effect in
                let fallbackName = "Effect \(index + 1)"
                let name = sanitizedFoundryText(
                    effect.name.isEmpty ? fallbackName : effect.name
                )
                return "**\(name)**\n\(projectedRuleEffectContent(effect))"
            }
            sections.append("**Effects**\n\n\(effects.joined(separator: "\n\n"))")
        }
        return sections.joined(separator: "\n\n")
    }

    func projectedRuleEffectContent(_ effect: FoundryRuleEffect) -> String {
        var lines = [
            "- **ID:** \(sanitizedFoundryText(effect.id))",
            "- **Disabled:** \(effect.isDisabled ? "yes" : "no")",
            "- **Transfers to actor:** \(effect.transfersToActor ? "yes" : "no")",
        ]
        if !effect.statuses.isEmpty {
            let statuses = effect.statuses.map { sanitizedFoundryText($0) }.joined(separator: ", ")
            lines.append("- **Statuses:** \(statuses)")
        }
        if let duration = effect.duration {
            lines.append("- **Duration:** \(presentedFoundryValue(duration))")
        }
        if !effect.changes.isEmpty {
            lines.append("**Changes**")
            lines.append(contentsOf: effect.changes.map { change in
                let path = sanitizedFoundryText(change.path)
                let operand = presentedFoundryValue(change.operand)
                let priority = change.priority.map { ", priority \($0)" } ?? ""
                return "- **\(path):** \(operand) (mode \(change.mode)\(priority))"
            })
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Assets

private extension FoundryMappingState {
    func createPackagedAssets() async throws {
        for resource in package.resources where resource.location == .packaged {
            try await cooperativeCheckpoint()
            guard let module = module(for: resource.logicalPath) else { continue }
            createAsset(resource, module: module)
        }
    }

    @discardableResult
    func createAsset(_ resource: FoundryPackageResource, module: NetworkModules) -> UUID {
        let key = ResourceKey(module: module, path: canonicalResourcePath(resource.logicalPath))
        if let existing = resourceIDs[key] { return existing }
        let id = stableID("asset#\(module.token)#\(key.path)")
        resourceIDs[key] = id
        let sourceFilename = resource.logicalPath.split(separator: "/").last.map(String.init)
            ?? resource.logicalPath
        let expectedMediaKind: FoundryMediaNormalizationPlan.Kind? = switch module {
        case .photo: .image
        case .audio: .audio
        default: nil
        }
        let normalizationPlan = FoundryMediaNormalizer.plan(
            for: resource.logicalPath,
            expectedKind: expectedMediaKind
        )
        let filename = normalizationPlan?.suggestedFilename
            ?? FoundryTextDecoder.decodedText(sourceFilename)
        let attachment: ExternalImportAttachment
        if module == .photo || module == .audio {
            guard let normalizationPlan else {
                warnings.append(
                    "Foundry media \(resource.logicalPath) has no safe raster or audio conversion and was not projected."
                )
                return id
            }
            attachment = ExternalImportAttachment(
                id: id,
                fileID: id,
                suggestedFilename: filename,
                contentTypeIdentifier: normalizationPlan.contentTypeIdentifier,
                expectedByteCount: nil,
                contentHash: nil,
                load: { [resourceLoader] in
                    let sourceData = try await resourceLoader(resource)
                    return try await normalizationPlan.normalize(sourceData)
                }
            )
        } else {
            attachment = ExternalImportAttachment(
                id: id,
                fileID: id,
                suggestedFilename: filename,
                contentTypeIdentifier: UTType(
                    filenameExtension: URL(filePath: filename).pathExtension
                )?.identifier,
                expectedByteCount: resource.byteCount,
                contentHash: resource.sha256.flatMap(base64Hash),
                load: { [resourceLoader] in try await resourceLoader(resource) }
            )
        }
        switch module {
        case .photo:
            let model = PhotoModel.empty(id)
            configureAsset(model, name: filename, category: .photo)
            add(model, module: module, sourceID: "asset:\(resource.logicalPath)", attachment: attachment)
        case .audio:
            let model = AudioModel.empty(id)
            configureAsset(model, name: filename, category: .music)
            add(model, module: module, sourceID: "asset:\(resource.logicalPath)", attachment: attachment)
        case .pdf:
            let model = PdfModel.empty(id)
            configureAsset(model, name: filename, category: .pdf)
            add(model, module: module, sourceID: "asset:\(resource.logicalPath)", attachment: attachment)
        case .space:
            let model = SpaceModel.empty(id)
            configureAsset(model, name: filename, category: .models)
            add(model, module: module, sourceID: "asset:\(resource.logicalPath)", attachment: attachment)
        default:
            break
        }
        return id
    }

    func configureAsset<Model: AnyObject & ItemDataAccessable>(_ model: Model, name: String, category: ItemListCategory) {
        var model = model
        model.name = name
        model.description = "Imported from \(packageName)."
        model.category = category
        model.tags = ["Foundry VTT"]
    }

    func mediaID(path: String?, module: NetworkModules) -> UUID? {
        guard selectedCategories.contains(.assets),
              let path,
              let resource = resource(matching: path),
              resource.location == .packaged else {
            return nil
        }
        let contextualPlan = FoundryMediaNormalizer.plan(
            for: resource.logicalPath,
            expectedKind: module == .audio ? .audio : nil
        )
        guard self.module(for: resource.logicalPath) == module
            || (module == .audio && contextualPlan?.kind == .audio) else {
            warnings.append("Foundry media reference \(path) is not a \(module.token) resource and was not projected into that module.")
            return nil
        }
        return createAsset(resource, module: module)
    }

    func assetLink(path: String?) -> String? {
        guard selectedCategories.contains(.assets),
              let path, let resource = resource(matching: path),
              let module = module(for: resource.logicalPath),
              resource.location == .packaged else { return nil }
        let id = createAsset(resource, module: module)
        let name = FoundryMediaNormalizer.plan(for: resource.logicalPath)?.suggestedFilename
            ?? resource.logicalPath.split(separator: "/").last.map {
                FoundryTextDecoder.decodedText(String($0))
            }
            ?? FoundryTextDecoder.decodedText(resource.logicalPath)
        return markdownLink(name: name, module: module, itemID: id)
    }

    func resource(matching path: String) -> FoundryPackageResource? {
        let canonicalPath = canonicalResourcePath(path)
        if let exact = resourcesByCanonicalPath[canonicalPath] {
            return exact
        }
        if ambiguousResourceCanonicalPaths.contains(canonicalPath) {
            return nil
        }
        let alias = resourceAlias(path)
        if let resource = resourcesByAlias[alias] {
            return resource
        }
        if ambiguousResourceAliases.contains(alias) {
            return nil
        }
        return nil
    }
}

// MARK: - Document dispatch

private extension FoundryMappingState {
    func mapDocument(_ document: FoundryDocument) {
        switch document.documentType {
        case .actor where selectedCategories.contains(.actors):
            mapActor(document)
        case .item where selectedCategories.contains(.items)
            || (selectedCategories.contains(.rules) && package.rulePackage == nil):
            mapItem(document)
        case .scene where selectedCategories.contains(.scenes):
            mapScene(document)
        case .journalEntry where selectedCategories.contains(.journals):
            mapJournal(document)
        case .rollTable where selectedCategories.contains(.tables):
            mapRollTable(document)
        case .playlist where selectedCategories.contains(.playlists):
            mapPlaylist(document)
        case .playlistSound where selectedCategories.contains(.playlists):
            mapStandaloneAudio(document)
        case .ambientSound where selectedCategories.contains(.scenes):
            mapStandaloneAudio(document)
        case .cards where selectedCategories.contains(.cards):
            mapCards(document)
        case .adventure where selectedCategories.contains(.adventures):
            mapAdventure(document)
        case .combat where selectedCategories.contains(.combats):
            mapCombat(document)
        case .macro where selectedCategories.contains(.macros):
            mapMacro(document)
        case .folder, .level, .journalEntryPage, .tableResult, .card, .user,
             .token, .wall, .ambientLight, .activeEffect, .combatant:
            break
        default:
            rawOnlyDocumentIDs.insert(document.id)
        }
    }

    func mapActor(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#character")
        var entries = hierarchicalEntries(
            document.rawData["system"],
            sourceID: document.id,
            ownerID: id,
            decisionOwnerID: id
        )
        for child in document.embeddedDocuments where child.documentType == .item {
            let childID = stableID("\(child.id)#character-item")
            let childModel = ValueModel(
                id: childID,
                name: child.name,
                description: safeText(child.descriptionHTML),
                tags: foundryTags(child),
                category: .item,
                displayState: DisplayStateMask.groupHidden.rawValue,
                photoId: mediaID(path: child.imagePath, module: .photo),
                entries: hierarchicalEntries(
                    child.rawData["system"],
                    sourceID: child.id,
                    ownerID: childID,
                    decisionOwnerID: id
                ),
                groupId: id
            )
            add(
                childModel,
                module: .value,
                sourceID: child.id,
                decisionOwnerID: id
            )
            entries.append(ValueEntryModel(
                id: stableID("\(document.id)#embedded-item#\(child.id)"),
                name: sanitizedFoundryText(child.name),
                type: .text,
                value: "",
                valueId: childID
            ))
        }
        let model = ValueModel(
            id: id,
            name: document.name,
            description: safeText(document.descriptionHTML),
            tags: foundryTags(document),
            category: actorCategory(document.subtype),
            photoId: mediaID(path: document.imagePath, module: .photo),
            entries: entries,
            parentId: folderID(for: document, module: .value)
        )
        add(model, module: .value, sourceID: document.id)
    }

    func mapItem(_ document: FoundryDocument) {
        if selectedCategories.contains(.items) {
            let id = stableID("\(document.id)#item")
            let model = ValueModel(
                id: id,
                name: document.name,
                description: safeText(document.descriptionHTML),
                tags: foundryTags(document),
                category: .item,
                photoId: mediaID(path: document.imagePath, module: .photo),
                entries: hierarchicalEntries(
                    document.rawData["system"],
                    sourceID: document.id,
                    ownerID: id,
                    decisionOwnerID: id
                ),
                parentId: folderID(for: document, module: .value)
            )
            add(model, module: .value, sourceID: document.id)
        }

        // System packages expose a richer normalized rule package and are projected above. World
        // and module Items do not, so preserve each standalone Item as an editable generic rule.
        if selectedCategories.contains(.rules), package.rulePackage == nil {
            let id = stableID("\(document.id)#rule")
            let filteredDocument = privacyFilteredDocumentsByID[document.id] ?? document
            let model = RuleModel.foundryDocument(
                id: id,
                name: filteredDocument.name,
                descriptionHTML: filteredDocument.descriptionHTML,
                tags: foundryTags(filteredDocument),
                documentType: filteredDocument.documentType.rawValue,
                subtype: filteredDocument.subtype ?? "",
                rawData: filteredDocument.rawData,
                parentId: folderID(for: document, module: .rule),
                packageIdentifier: packageIdentifier,
                identityNamespace: "external-source:\(sourceScopeID.uuidString.lowercased())#rule#\(document.id)"
            )
            prepareGenericRuleProjection(
                model,
                descriptionHTML: filteredDocument.descriptionHTML
            )
            add(model, module: .rule, sourceID: document.id)
        }
    }

    func mapScene(_ document: FoundryDocument) {
        guard let geometry = FoundryProjectionGeometry.sceneGeometry(in: document.rawData) else {
            emitGeometryWarning(.scene)
            rawOnlyDocumentIDs.insert(document.id)
            return
        }
        let levels = document.embeddedDocuments.filter { $0.documentType == .level }
        if !levels.isEmpty {
            mapLeveledScene(document, levels: levels, geometry: geometry)
            return
        }

        let id = stableID("\(document.id)#map")
        let imagePath = document.rawData.value(at: "background.src")?.stringValue ?? document.imagePath
        let photoID = mediaID(path: imagePath, module: .photo)
        let ambientAudioLinks = projectedAmbientAudioLinks(
            in: document.embeddedDocuments.filter { $0.documentType == .ambientSound }
        )
        let tokens = document.embeddedDocuments.filter { $0.documentType == .token }
        let mappedPins = tokens.compactMap { token -> (source: FoundryDocument, model: MapPinModel)? in
            guard let pin = tokenPin(token, gridSize: geometry.gridSize) else {
                emitGeometryWarning(.token)
                rawOnlyDocumentIDs.insert(token.id)
                return nil
            }
            return (token, pin)
        }
        let wallDocuments = document.embeddedDocuments.filter { $0.documentType == .wall }
        let mappedWalls = wallDocuments.compactMap { wall in
            mapWall(wall).map { (source: wall, model: $0) }
        }
        let walls = mappedWalls.map(\.model)
        let model = MapModel(
            id: id,
            name: document.name,
            description: appendingAmbientAudio(
                ambientAudioLinks,
                to: safeText(document.descriptionHTML)
            ),
            tags: foundryTags(document),
            category: .dungeon,
            photoId: photoID,
            width: geometry.width,
            height: geometry.height,
            mapPins: mappedPins.map(\.model),
            walls: walls,
            hexMapScale: geometry.gridSize,
            parentId: folderID(for: document, module: .map)
        )
        add(model, module: .map, sourceID: document.id)
        for pin in mappedPins {
            recordMapping(sourceID: pin.source.id, module: .map, itemID: id, entryID: pin.model.id)
        }
        for wall in mappedWalls {
            recordMapping(sourceID: wall.source.id, module: .map, itemID: id, entryID: wall.model.id)
        }
        for child in document.embeddedDocuments where !sceneHandledTypes.contains(child.documentType) {
            rawOnlyDocumentIDs.insert(child.id)
        }
    }

    func mapLeveledScene(
        _ document: FoundryDocument,
        levels: [FoundryDocument],
        geometry: FoundrySceneProjectionGeometry
    ) {
        let groupID = stableID("\(document.id)#level-group")
        let group = MapModel(
            id: groupID,
            name: document.name,
            description: safeText(document.descriptionHTML),
            tags: foundryTags(document),
            category: .folder,
            parentId: folderID(for: document, module: .map)
        )
        add(group, module: .map, sourceID: "\(document.id)#level-group")

        let initialLevel = initialLevel(in: document, levels: levels)
        let initialDocumentID = initialLevel.documentID
        let directTokens = document.embeddedDocuments
            .filter { $0.documentType == .token }
            .map { LeveledChild(document: $0, containingLevel: nil) }
        let nestedTokens = levels.flatMap { level in
            level.embeddedDocuments
                .filter { $0.documentType == .token }
                .map { LeveledChild(document: $0, containingLevel: level) }
        }
        let directWalls = document.embeddedDocuments
            .filter { $0.documentType == .wall }
            .map { LeveledChild(document: $0, containingLevel: nil) }
        let nestedWalls = levels.flatMap { level in
            level.embeddedDocuments
                .filter { $0.documentType == .wall }
                .map { LeveledChild(document: $0, containingLevel: level) }
        }
        let directAmbientSounds = document.embeddedDocuments
            .filter { $0.documentType == .ambientSound }
            .map { LeveledChild(document: $0, containingLevel: nil) }
        let nestedAmbientSounds = levels.flatMap { level in
            level.embeddedDocuments
                .filter { $0.documentType == .ambientSound }
                .map { LeveledChild(document: $0, containingLevel: level) }
        }
        let tokensByLevel = assignLevelMembership(
            directTokens + nestedTokens,
            levels: levels,
            initialLevel: initialLevel,
            kind: "Token"
        )
        let wallsByLevel = assignLevelMembership(
            directWalls + nestedWalls,
            levels: levels,
            initialLevel: initialLevel,
            kind: "Wall"
        )
        let ambientSoundsByLevel = assignLevelMembership(
            directAmbientSounds + nestedAmbientSounds,
            levels: levels,
            initialLevel: initialLevel,
            kind: "Ambient sound"
        )

        for level in levels {
            let isInitial = level.documentID == initialDocumentID
            let id = levelMapIDs[level.id] ?? stableID("\(level.id)#level-map")
            let backgroundPath = level.rawData.value(at: "background.src")?.stringValue
                ?? document.rawData.value(at: "background.src")?.stringValue
                ?? document.imagePath
            let foregroundPath = level.rawData.value(at: "foreground.src")?.stringValue
                ?? document.rawData.value(at: "foreground.src")?.stringValue
            let minimumElevation = projectedLevelElevation(level.rawData.value(at: "elevation.bottom"))
            let maximumElevation = projectedLevelElevation(level.rawData.value(at: "elevation.top"))
            let tokens = tokensByLevel[level.id] ?? []
            let mappedPins = tokens.compactMap { token -> (source: FoundryDocument, model: MapPinModel)? in
                guard let pin = tokenPin(token, gridSize: geometry.gridSize) else {
                    emitGeometryWarning(.token)
                    rawOnlyDocumentIDs.insert(token.id)
                    return nil
                }
                return (token, pin)
            }
            let mappedWalls = (wallsByLevel[level.id] ?? []).compactMap { wall in
                mapWall(
                    wall,
                    minimumElevation: minimumElevation,
                    maximumElevation: maximumElevation,
                    levelIdentifier: level.documentID,
                    identitySuffix: level.id
                ).map { (source: wall, model: $0) }
            }
            var description = safeText(document.descriptionHTML)
            let elevation = [
                minimumElevation.map { "bottom \($0.formatted())" },
                maximumElevation.map { "top \($0.formatted())" }
            ].compactMap { $0 }.joined(separator: ", ")
            if !elevation.isEmpty {
                description += "\(description.isEmpty ? "" : "\n\n")Elevation: \(elevation)"
            }
            if let foreground = assetLink(path: foregroundPath) {
                description += "\(description.isEmpty ? "" : "\n\n")Foreground: \(foreground)"
            }
            description = appendingAmbientAudio(
                projectedAmbientAudioLinks(in: ambientSoundsByLevel[level.id] ?? []),
                to: description
            )
            let model = MapModel(
                id: id,
                name: levels.count == 1 ? document.name : "\(document.name) — \(level.name)",
                description: description,
                tags: foundryTags(document) + ["Foundry Level"],
                category: .dungeon,
                photoId: mediaID(path: backgroundPath, module: .photo),
                width: geometry.width,
                height: geometry.height,
                mapPins: mappedPins.map(\.model),
                walls: mappedWalls.map(\.model),
                hexMapScale: geometry.gridSize,
                parentId: groupID
            )
            add(model, module: .map, sourceID: level.id)
            if isInitial {
                recordMapping(sourceID: document.id, module: .map, itemID: id)
            }
            for pin in mappedPins {
                recordMapping(sourceID: pin.source.id, module: .map, itemID: id, entryID: pin.model.id)
            }
            for wall in mappedWalls {
                recordMapping(sourceID: wall.source.id, module: .map, itemID: id, entryID: wall.model.id)
            }
        }

        for child in document.embeddedDocuments where !sceneHandledTypes.contains(child.documentType) {
            rawOnlyDocumentIDs.insert(child.id)
        }
    }

    func mapJournal(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#journal")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .adventure
        model.parentId = folderID(for: document, module: .adventure)
        let pages = document.embeddedDocuments.filter { $0.documentType == .journalEntryPage }
        if pages.isEmpty {
            model.entries = [AdventureEntryModel(
                id: stableID("\(document.id)#content"),
                name: sanitizedFoundryText(document.name),
                content: safeText(document.descriptionHTML)
            )]
        } else {
            model.entries = pages.map { page in
                var content = safeText(page.descriptionHTML)
                let sourcePath = page.rawData["src"]?.stringValue
                    ?? page.rawData.value(at: "image.src")?.stringValue
                    ?? page.rawData.value(at: "video.src")?.stringValue
                if let link = assetLink(path: sourcePath) {
                    content += "\(content.isEmpty ? "" : "\n\n")\(link)"
                }
                let entry = AdventureEntryModel(
                    id: stableID("\(page.id)#entry"),
                    name: sanitizedFoundryText(page.name),
                    content: rewriteFoundryLinks(content)
                )
                recordMapping(sourceID: page.id, module: .adventure, itemID: id, entryID: entry.id)
                return entry
            }
        }
        add(model, module: .adventure, sourceID: document.id)
    }

    func mapRollTable(_ document: FoundryDocument) {
        let tableID = stableID("\(document.id)#table")
        let formula = document.rawData["formula"]?.stringValue
        let diceID = formula.flatMap { createDice(formula: $0, name: document.name, sourceID: document.id) }
        let model = TableModel.empty(tableID)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = tableCategory(document)
        model.tableType = diceID == nil ? .list : .dice
        model.diceId = diceID
        model.parentId = folderID(for: document, module: .table)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .tableResult }
            .map { result in
                var entry = TableEntryModel.empty(stableID("\(result.id)#table-entry"))
                entry.name = sanitizedFoundryText(result.name)
                let range = result.rawData["range"]?.arrayValue?.compactMap(number).map { $0.formatted() }.joined(separator: "–")
                let weight = number(result.rawData["weight"])
                var details = safeText(result.descriptionHTML)
                if details.isEmpty { details = result.rawData["text"]?.stringValue.map(safeText) ?? "" }
                if let link = assetLink(path: result.imagePath) {
                    details += "\(details.isEmpty ? "" : "\n")\(link)"
                }
                let metadata = [
                    range.map { "Range: \($0)" },
                    weight.map { "Weight: \($0.formatted())" }
                ].compactMap { $0 }.joined(separator: "; ")
                entry.content = [details, metadata].filter { !$0.isEmpty }.joined(separator: "\n")
                recordMapping(sourceID: result.id, module: .table, itemID: tableID, entryID: entry.id)
                return entry
            }
        add(model, module: .table, sourceID: document.id)
    }

    func mapPlaylist(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#playlist")
        let model = AudioModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .playlist
        model.parentId = folderID(for: document, module: .audio)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .playlistSound }
            .compactMap { sound in
                let path = sound.rawData["path"]?.stringValue ?? sound.rawData["src"]?.stringValue
                guard let audioID = mediaID(path: path, module: .audio) else {
                    rawOnlyDocumentIDs.insert(sound.id)
                    return nil
                }
                recordMapping(sourceID: sound.id, module: .audio, itemID: audioID)
                return AudioEntryModel(
                    id: stableID("\(document.id)#sound-edge#\(sound.id)"),
                    audioId: audioID
                )
            }
        add(model, module: .audio, sourceID: document.id)
    }

    func mapStandaloneAudio(_ document: FoundryDocument) {
        let path = firstString(
            document.rawData,
            paths: ["path", "src", "sound.src", "source"]
        )
        guard let audioID = mediaID(path: path, module: .audio) else {
            rawOnlyDocumentIDs.insert(document.id)
            return
        }
        recordMapping(sourceID: document.id, module: .audio, itemID: audioID)
    }

    func mapCards(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#cards")
        let model = TableModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .collection
        model.parentId = folderID(for: document, module: .table)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .card }
            .map { card in
                var entry = TableEntryModel.empty(stableID("\(card.id)#card-entry"))
                entry.name = sanitizedFoundryText(card.name)
                var content = safeText(card.descriptionHTML)
                if let link = assetLink(path: card.imagePath) {
                    content += "\(content.isEmpty ? "" : "\n")\(link)"
                }
                let state = [
                    card.rawData["drawn"]?.boolValue.map { "Drawn: \($0 ? "yes" : "no")" },
                    card.rawData["sort"]?.integerValue.map { "Sort: \($0)" }
                ].compactMap { $0 }.joined(separator: "; ")
                entry.content = [content, state].filter { !$0.isEmpty }.joined(separator: "\n")
                recordMapping(sourceID: card.id, module: .table, itemID: id, entryID: entry.id)
                return entry
            }
        add(model, module: .table, sourceID: document.id)
    }

    func mapAdventure(_ document: FoundryDocument) {
        for child in document.embeddedDocuments {
            mapDocument(child)
        }
        let id = stableID("\(document.id)#adventure")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = safeText(document.descriptionHTML)
        model.tags = foundryTags(document)
        model.category = .campaign
        model.parentId = folderID(for: document, module: .adventure)
        model.entries = document.embeddedDocuments.flatMap { child in
            (mappingReferences[child.id] ?? []).map { reference in
                AdventureEntryModel(
                    id: stableID("\(document.id)#link#\(child.id)#\(reference.module.token)#\(reference.itemID)"),
                    name: sanitizedFoundryText(child.name),
                    content: markdownLink(
                        name: sanitizedFoundryText(child.name),
                        module: reference.module,
                        itemID: reference.itemID
                    )
                )
            }
        }
        add(model, module: .adventure, sourceID: document.id)
    }

    func mapCombat(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#combat")
        let model = AdventureModel.empty(id)
        model.name = document.name.isEmpty ? "Combat" : document.name
        model.description = "Imported Foundry combat state. It is reference material and does not become a live MasterRPG encounter."
        model.tags = foundryTags(document)
        model.category = .scenario
        model.parentId = folderID(for: document, module: .adventure)
        model.entries = document.embeddedDocuments
            .filter { $0.documentType == .combatant }
            .map { combatant in
                let entry = AdventureEntryModel(
                    id: stableID("\(combatant.id)#combat-entry"),
                    name: sanitizedFoundryText(combatant.name),
                    content: combatantSummary(combatant)
                )
                recordMapping(sourceID: combatant.id, module: .adventure, itemID: id, entryID: entry.id)
                return entry
            }
        add(model, module: .adventure, sourceID: document.id)
    }

    func mapMacro(_ document: FoundryDocument) {
        let id = stableID("\(document.id)#macro")
        let model = AdventureModel.empty(id)
        model.name = document.name
        model.description = "Foundry macro imported as non-executable text."
        model.tags = foundryTags(document) + ["Non-executable"]
        model.category = .supplement
        model.parentId = folderID(for: document, module: .adventure)
        let command = document.rawData["command"]?.stringValue ?? ""
        model.entries = [AdventureEntryModel(
            id: stableID("\(document.id)#macro-source"),
            name: "Source (never executed)",
            content: inertCodeBlock(command)
        )]
        add(model, module: .adventure, sourceID: document.id, warnings: ["Macro code is stored as text and is never executed."])
    }

    func mapChatTranscript(_ collection: FoundryDocumentCollection) {
        let messages = collection.documents.filter { $0.documentType == .chatMessage }
        guard !messages.isEmpty else { return }
        let id = stableID("\(collection.id)#chat-transcript")
        let model = AdventureModel.empty(id)
        model.name = "\(sanitizedFoundryText(collection.label)) – Chat transcript"
        model.description = "Foundry chat history. Review private, blind, and whispered messages before sharing."
        model.tags = ["Foundry VTT", "Private import"]
        model.category = .supplement
        model.entries = messages.map { message in
            let speaker = message.rawData.value(at: "speaker.alias")?.stringValue ?? message.name
            let timestamp = message.rawData["timestamp"]?.integerValue
            let content = message.rawData["content"]?.stringValue ?? message.descriptionHTML ?? ""
            let dateText = timestamp.map { Date(timeIntervalSince1970: TimeInterval($0 / 1_000)).formatted(date: .abbreviated, time: .shortened) }
            let entry = AdventureEntryModel(
                id: stableID("\(message.id)#chat-entry"),
                name: [speaker, dateText]
                    .compactMap { $0 }
                    .map(sanitizedFoundryText)
                    .filter { !$0.isEmpty }
                    .joined(separator: " – "),
                content: rewriteFoundryLinks(safeText(content))
            )
            recordMapping(sourceID: message.id, module: .adventure, itemID: id, entryID: entry.id)
            return entry
        }
        add(model, module: .adventure, sourceID: "\(collection.id)#chat")
    }
}

// MARK: - Scene conversion

private extension FoundryMappingState {
    struct LeveledChild {
        let document: FoundryDocument
        let containingLevel: FoundryDocument?
    }

    var sceneHandledTypes: Set<FoundryDocumentType> {
        [.level, .token, .wall, .ambientSound]
    }

    func projectedAmbientAudioLinks(in sounds: [FoundryDocument]) -> [String] {
        sounds.compactMap { sound in
            let path = firstString(
                sound.rawData,
                paths: ["path", "src", "sound.src", "source"]
            )
            guard let path,
                  let resource = resource(matching: path),
                  let audioID = mediaID(path: path, module: .audio) else {
                rawOnlyDocumentIDs.insert(sound.id)
                return nil
            }
            recordMapping(sourceID: sound.id, module: .audio, itemID: audioID)
            let importedFilename = FoundryMediaNormalizer.plan(
                for: resource.logicalPath,
                expectedKind: .audio
            )?.suggestedFilename
            let documentName = sanitizedFoundryText(sound.name)
            let fallbackName = importedFilename
                ?? URL(filePath: resource.logicalPath).lastPathComponent
            let name = documentName.isEmpty ? fallbackName : documentName
            return markdownLink(name: name, module: .audio, itemID: audioID)
        }
    }

    func appendingAmbientAudio(_ links: [String], to description: String) -> String {
        guard !links.isEmpty else { return description }
        let section = "**Ambient audio**\n\(links.map { "- \($0)" }.joined(separator: "\n"))"
        return [description, section].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func initialLevel(in scene: FoundryDocument, levels: [FoundryDocument]) -> FoundryDocument {
        precondition(!levels.isEmpty)
        if let requested = foundryIdentifier(scene.rawData["initialLevel"]) {
            if let level = matchingLevel(requested, in: levels) {
                return level
            }
            warnings.append("Scene \(scene.name) names unknown initial level \(requested); the first source level is used instead.")
        }

        // `embeddedDocuments` is sorted for stable presentation. Preserve Foundry's source-array
        // order for the semantic fallback required when Scene.initialLevel is absent or invalid.
        for sourceLevel in scene.rawData["levels"]?.arrayValue ?? [] {
            guard let identifier = foundryIdentifier(sourceLevel),
                  let level = matchingLevel(identifier, in: levels) else { continue }
            return level
        }
        return levels[0]
    }

    func assignLevelMembership(
        _ children: [LeveledChild],
        levels: [FoundryDocument],
        initialLevel: FoundryDocument,
        kind: String
    ) -> [String: [FoundryDocument]] {
        var result: [String: [FoundryDocument]] = [:]
        for child in children {
            let explicitIdentifier = explicitLevelIdentifier(in: child.document)
            let target: FoundryDocument?
            if let explicitIdentifier {
                target = matchingLevel(explicitIdentifier, in: levels)
                if target == nil {
                    warnings.append("\(kind) \(child.document.name) names unknown level \(explicitIdentifier); it remains only in the raw archive.")
                    rawOnlyDocumentIDs.insert(child.document.id)
                }
            } else {
                target = child.containingLevel ?? initialLevel
            }
            guard let target else { continue }
            result[target.id, default: []].append(child.document)
        }
        return result
    }

    func explicitLevelIdentifier(in document: FoundryDocument) -> String? {
        let candidates = [
            document.rawData["level"],
            document.rawData["levelId"],
            document.rawData.value(at: "flags.levels.levelId"),
            document.rawData.value(at: "flags.levels.level"),
        ]
        return candidates.lazy.compactMap(foundryIdentifier).first
    }

    func matchingLevel(_ identifier: String, in levels: [FoundryDocument]) -> FoundryDocument? {
        levels.first { level in
            level.documentID == identifier
                || level.id == identifier
                || level.sourceUUID == identifier
                || level.rawData["uuid"]?.stringValue == identifier
        }
    }

    func foundryIdentifier(_ value: FoundryJSONValue?) -> String? {
        let identifier: String? = switch value {
        case .string(let value): value
        case .object(let object):
            object["_id"]?.stringValue
                ?? object["id"]?.stringValue
                ?? object["uuid"]?.stringValue
        default: nil
        }
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty else { return nil }
        return identifier
    }

    func projectedLevelElevation(_ value: FoundryJSONValue?) -> Double? {
        guard let value else { return nil }
        guard let elevation = FoundryProjectionGeometry.coordinate(value) else {
            emitGeometryWarning(.levelElevation)
            return nil
        }
        return elevation
    }

    func emitGeometryWarning(_ warning: FoundryGeometryWarning) {
        guard emittedGeometryWarnings.insert(warning).inserted else { return }
        warnings.append(warning.message)
    }

    func tokenPin(_ token: FoundryDocument, gridSize: Double) -> MapPinModel? {
        guard let x = FoundryProjectionGeometry.coordinate(token.rawData["x"], defaultValue: 0),
              let y = FoundryProjectionGeometry.coordinate(token.rawData["y"], defaultValue: 0),
              let width = FoundryProjectionGeometry.tokenDimension(
                  token.rawData["width"],
                  defaultValue: 1
              ),
              let height = FoundryProjectionGeometry.tokenDimension(
                  token.rawData["height"],
                  defaultValue: 1
              ),
              let centerX = FoundryProjectionGeometry.tokenCenter(
                  origin: x,
                  gridUnits: width,
                  gridSize: gridSize
              ),
              let centerY = FoundryProjectionGeometry.tokenCenter(
                  origin: y,
                  gridUnits: height,
                  gridSize: gridSize
              ) else { return nil }
        let actorID = token.rawData["actorId"]?.stringValue.flatMap { actorsByDocumentID[$0] }
        let texture = token.rawData.value(at: "texture.src")?.stringValue ?? token.imagePath
        let units = max(width, height)
        let size: MapPinModel.MapPinSize = switch units {
        case ..<0.75: .tiny
        case ..<1: .small
        case ..<2: .normal
        case ..<3: .large
        case ..<4: .huge
        default: .colossal
        }
        return MapPinModel(
            id: stableID("\(token.id)#map-pin"),
            name: token.name,
            photoId: mediaID(path: texture, module: .photo),
            characterId: actorID,
            location: CGPoint(x: centerX, y: centerY),
            size: size,
            isShown: !(token.rawData["hidden"]?.boolValue ?? false),
            isDead: token.rawData.value(at: "overlayEffect")?.stringValue?.localizedCaseInsensitiveContains("dead") ?? false
        )
    }

    func mapWall(
        _ wall: FoundryDocument,
        minimumElevation: Double? = nil,
        maximumElevation: Double? = nil,
        levelIdentifier: String? = nil,
        identitySuffix: String? = nil
    ) -> MapWallModel? {
        guard let rawCoordinates = wall.rawData["c"]?.arrayValue, rawCoordinates.count >= 4 else {
            emitGeometryWarning(.wall)
            rawOnlyDocumentIDs.insert(wall.id)
            return nil
        }
        let coordinates = rawCoordinates.prefix(4).compactMap {
            FoundryProjectionGeometry.coordinate($0)
        }
        guard coordinates.count == 4,
              let movementRestriction = FoundryProjectionGeometry.exactInteger(
                  wall.rawData["move"],
                  defaultValue: 20
              ),
              let sightRestriction = FoundryProjectionGeometry.exactInteger(
                  wall.rawData["sight"],
                  defaultValue: 20
              ),
              let doorType = FoundryProjectionGeometry.exactInteger(
                  wall.rawData["door"],
                  defaultValue: 0
              ),
              let doorState = FoundryProjectionGeometry.exactInteger(
                  wall.rawData["ds"],
                  defaultValue: 0
              ) else {
            emitGeometryWarning(.wall)
            rawOnlyDocumentIDs.insert(wall.id)
            return nil
        }
        let rawMinimumElevation = firstValue(
            wall.rawData,
            paths: ["flags.wall-height.bottom", "flags.levels.rangeBottom"]
        )
        let rawMaximumElevation = firstValue(
            wall.rawData,
            paths: ["flags.wall-height.top", "flags.levels.rangeTop"]
        )
        let resolvedMinimumElevation: Double?
        if let rawMinimumElevation {
            guard let value = FoundryProjectionGeometry.coordinate(rawMinimumElevation) else {
                emitGeometryWarning(.wall)
                rawOnlyDocumentIDs.insert(wall.id)
                return nil
            }
            resolvedMinimumElevation = value
        } else {
            resolvedMinimumElevation = minimumElevation
        }
        let resolvedMaximumElevation: Double?
        if let rawMaximumElevation {
            guard let value = FoundryProjectionGeometry.coordinate(rawMaximumElevation) else {
                emitGeometryWarning(.wall)
                rawOnlyDocumentIDs.insert(wall.id)
                return nil
            }
            resolvedMaximumElevation = value
        } else {
            resolvedMaximumElevation = maximumElevation
        }
        let identity = identitySuffix.map { "\(wall.id)#wall#\($0)" } ?? "\(wall.id)#wall"
        let sourceIdentifier = identitySuffix.map { "\(wall.id)#level#\($0)" } ?? wall.id
        return MapWallModel(
            id: stableID(identity),
            sourceIdentifier: sourceIdentifier,
            start: CGPoint(x: coordinates[0], y: coordinates[1]),
            end: CGPoint(x: coordinates[2], y: coordinates[3]),
            movementRestriction: .init(rawValue: movementRestriction),
            sightRestriction: .init(rawValue: sightRestriction),
            doorType: .init(rawValue: doorType),
            doorState: .init(rawValue: doorState),
            minimumElevation: resolvedMinimumElevation,
            maximumElevation: resolvedMaximumElevation,
            levelIdentifier: firstString(wall.rawData, paths: ["flags.levels.levelId", "flags.levels.level"])
                ?? levelIdentifier,
            rawMetadata: wall.rawData
        )
    }
}

// MARK: - Dice and values

private extension FoundryMappingState {
    func createDice(formula: String, name: String, sourceID: String) -> UUID? {
        let range = NSRange(formula.startIndex..<formula.endIndex, in: formula)
        // MasterRPG can represent additive dice plus a numeric modifier. Foundry roll syntax also
        // supports pools, keep/drop, functions, variables, comparisons, and multiplication. Never
        // project a matching substring from those richer expressions as if it were equivalent.
        let supportedGrammar = try? NSRegularExpression(
            pattern: #"^\s*[0-9]*[dD][0-9]+(?:\s*(?:\+\s*[0-9]*[dD][0-9]+|[+-]\s*[0-9]+(?:\.[0-9]+)?))*\s*$"#
        )
        guard supportedGrammar?.firstMatch(in: formula, range: range)?.range == range else {
            warnings.append("Roll formula ‘\(formula)’ uses Foundry syntax that is not exactly representable; it remains text in the raw archive.")
            return nil
        }

        let pattern = try? NSRegularExpression(pattern: #"([0-9]*)[dD]([0-9]+)"#)
        let matches = pattern?.matches(in: formula, range: range) ?? []
        var dice: [DieModel] = []
        for match in matches {
            guard let sidesRange = Range(match.range(at: 2), in: formula),
                  let sides = Int(formula[sidesRange]), sides > 0 else {
                warnings.append("Roll formula ‘\(formula)’ contains an invalid die and remains text in the raw archive.")
                return nil
            }
            let count: Int
            if let countRange = Range(match.range(at: 1), in: formula), !countRange.isEmpty {
                guard let parsedCount = Int(formula[countRange]), (1...100).contains(parsedCount) else {
                    warnings.append("Roll formula ‘\(formula)’ exceeds the supported limit of 100 dice and remains text in the raw archive.")
                    return nil
                }
                count = parsedCount
            } else {
                count = 1
            }
            for index in 0..<count {
                dice.append(DieModel(
                    id: stableID("\(sourceID)#die#\(match.range.location)#\(index)"),
                    die: RawDie(text: "d\(sides)")
                ))
            }
        }
        guard !dice.isEmpty else {
            warnings.append("Roll formula ‘\(formula)’ is preserved as text because it has no directly representable dice.")
            return nil
        }
        let modifier = simpleModifier(formula)
        guard modifier.isFinite else {
            warnings.append("Roll formula ‘\(formula)’ has a modifier outside the supported numeric range and remains text in the raw archive.")
            return nil
        }
        let id = stableID("\(sourceID)#dice")
        let model = DiceModel(
            id: id,
            name: "\(name) (\(formula))",
            description: "Original Foundry formula: \(formula)",
            tags: ["Foundry VTT"],
            category: .rules,
            dice: dice,
            modifier: modifier
        )
        add(model, module: .dice, sourceID: "\(sourceID)#formula")
        return id
    }

    func hierarchicalEntries(
        _ value: FoundryJSONValue?,
        sourceID: String,
        ownerID: UUID,
        decisionOwnerID: UUID
    ) -> [ValueEntryModel] {
        guard let value else { return [] }
        let nodes = FoundryValueHierarchy.nodes(from: value)
        let valueCount = nodes.reduce(0) { $0 + $1.valueCount }
        let maximumPresentedValues = 500
        if valueCount > maximumPresentedValues {
            warnings.append(
                "\(sourceID) has \(valueCount) system fields; the display projection includes the first \(maximumPresentedValues) and the archive retains all fields."
            )
        }
        var remainingValues = maximumPresentedValues
        return projectedValueEntries(
            nodes,
            sourceID: sourceID,
            ownerID: ownerID,
            decisionOwnerID: decisionOwnerID,
            remainingValues: &remainingValues
        )
    }

    func projectedValueEntries(
        _ nodes: [FoundryValueNode],
        sourceID: String,
        ownerID: UUID,
        decisionOwnerID: UUID,
        remainingValues: inout Int
    ) -> [ValueEntryModel] {
        var entries: [ValueEntryModel] = []
        for node in nodes {
            guard remainingValues > 0 else { break }
            let pathIdentity = valuePathIdentity(node.pathComponents)
            if node.children.isEmpty, let value = node.value {
                remainingValues -= 1
                let presentation = valuePresentation(value)
                entries.append(ValueEntryModel(
                    id: stableID("\(sourceID)#field#\(pathIdentity)"),
                    name: FoundryTextDecoder.decodedText(node.component),
                    type: presentation.type,
                    value: presentation.value
                ))
                continue
            }

            let groupID = stableID("\(sourceID)#field-group#\(pathIdentity)")
            var childEntries: [ValueEntryModel] = []
            if let value = node.value, remainingValues > 0 {
                remainingValues -= 1
                let presentation = valuePresentation(value)
                childEntries.append(ValueEntryModel(
                    id: stableID("\(sourceID)#field#\(pathIdentity)#value"),
                    name: "value",
                    type: presentation.type,
                    value: presentation.value
                ))
            }
            childEntries.append(contentsOf: projectedValueEntries(
                node.children,
                sourceID: sourceID,
                ownerID: groupID,
                decisionOwnerID: decisionOwnerID,
                remainingValues: &remainingValues
            ))
            guard !childEntries.isEmpty else { continue }

            let groupName = FoundryTextDecoder.decodedText(node.component)
            let groupModel = ValueModel(
                id: groupID,
                name: groupName,
                category: .item,
                displayState: DisplayStateMask.groupHidden.rawValue,
                entries: childEntries,
                groupId: ownerID
            )
            add(
                groupModel,
                module: .value,
                sourceID: sourceID,
                decisionOwnerID: decisionOwnerID
            )
            entries.append(ValueEntryModel(
                id: stableID("\(sourceID)#field-group-link#\(pathIdentity)"),
                name: groupName,
                type: .text,
                value: "",
                valueId: groupID
            ))
        }
        return entries
    }

    func valuePathIdentity(_ components: [String]) -> String {
        guard !components.isEmpty else { return "root" }
        return components.map { component in
            "\(component.utf8.count):\(component)"
        }.joined()
    }

    func valuePresentation(_ value: FoundryJSONValue) -> (type: ValueEntryModel.ValueType, value: String) {
        switch value {
        case .integer(let value): (.number, String(value))
        case .unsignedInteger(let value): (.number, String(value))
        case .number(let value): (.decimal, String(value))
        case .bool(let value): (.selection, value ? "I" : "")
        case .string(let value): (.text, decodedFoundryText(value))
        case .array, .object: (.text, displayString(value))
        case .null: (.text, "")
        }
    }
}

// MARK: - Shared conversion helpers

private extension FoundryMappingState {
    struct DestinationKey: Hashable {
        let module: NetworkModules
        let id: UUID
    }

    struct FolderKey: Hashable {
        let module: NetworkModules
        let documentType: FoundryDocumentType
        let scope: String
        let foundryID: String
    }

    struct FolderAliasKey: Hashable {
        let module: NetworkModules
        let documentType: FoundryDocumentType
        let foundryID: String
    }

    struct FolderDeclaration {
        let id: String
        let documentID: String
        let name: String
        let parentID: String?
        let documentType: FoundryDocumentType
        let scope: String
    }

    struct ResourceKey: Hashable {
        let module: NetworkModules
        let path: String
    }

    struct Destination: Hashable {
        let module: NetworkModules
        let itemID: UUID
    }

    func add<Model>(
        _ model: Model,
        module: NetworkModules,
        sourceID: String,
        attachment: ExternalImportAttachment? = nil,
        decisionOwnerID: UUID? = nil,
        warnings: [String] = []
    ) where Model: ItemDataAccessable & Observable {
        var model = model
        model.name = sanitizedFoundryText(model.name)
        let key = DestinationKey(module: module, id: model.id)
        recordMapping(sourceID: sourceID, module: module, itemID: model.id)
        guard emittedItems.insert(key).inserted else { return }
        items.append(ExternalImportBatchItem(
            id: model.id,
            module: module,
            name: model.name,
            model: model,
            provenance: ExternalImportProvenance(
                source: provenance.source,
                sourceScopeID: provenance.sourceScopeID,
                packageIdentifier: packageIdentifier,
                documentIdentifier: sourceID,
                sourcePath: sourceURL.lastPathComponent,
                sourceVersion: provenance.sourceVersion
            ),
            attachment: attachment,
            decisionOwnerID: decisionOwnerID,
            warnings: warnings
        ))
    }

    func recordMapping(sourceID: String, module: NetworkModules, itemID: UUID, entryID: UUID? = nil) {
        mappingReferences[sourceID, default: []].insert(
            FoundryImportMappingReference(module: module, itemID: itemID, entryID: entryID)
        )
    }

    func stableID(_ component: String) -> UUID {
        FoundryRuleIdentity.uuid(for: "external-source:\(sourceScopeID.uuidString.lowercased())#\(component)")
    }

    func mappingOrder(_ lhs: FoundryImportMappingReference, _ rhs: FoundryImportMappingReference) -> Bool {
        if lhs.module.rawValue != rhs.module.rawValue { return lhs.module.rawValue < rhs.module.rawValue }
        if lhs.itemID != rhs.itemID { return lhs.itemID.uuidString < rhs.itemID.uuidString }
        return (lhs.entryID?.uuidString ?? "") < (rhs.entryID?.uuidString ?? "")
    }

    func folderID(for document: FoundryDocument, module: NetworkModules) -> UUID? {
        document.folderID.flatMap {
            resolveFolder(
                module: module,
                documentType: document.documentType,
                scope: canonicalScope(of: document.id, fallback: document.parentID ?? packageIdentifier),
                foundryID: $0
            )
        }
    }

    func modules(for type: FoundryDocumentType) -> [NetworkModules] {
        if type == .item {
            var result: [NetworkModules] = []
            if selectedCategories.contains(.items) {
                result.append(.value)
            }
            if selectedCategories.contains(.rules), package.rulePackage == nil {
                result.append(.rule)
            }
            return result
        }
        let mapping: (FoundryImportCategory, [NetworkModules])? = switch type {
        case .actor: (.actors, [.value])
        case .scene, .level: (.scenes, [.map])
        case .journalEntry: (.journals, [.adventure])
        case .adventure: (.adventures, [.adventure])
        case .combat: (.combats, [.adventure])
        case .chatMessage: (.chat, [.adventure])
        case .macro: (.macros, [.adventure])
        case .rollTable: (.tables, [.table])
        case .playlist: (.playlists, [.audio])
        case .cards: (.cards, [.table])
        default: nil
        }
        guard let mapping, selectedCategories.contains(mapping.0) else { return [] }
        return mapping.1
    }

    func predictedDestination(for document: FoundryDocument) -> Destination? {
        switch document.documentType {
        case .actor where selectedCategories.contains(.actors):
            Destination(module: .value, itemID: stableID("\(document.id)#character"))
        case .item:
            if let parentID = document.parentID, documentTypesByID[parentID] == .actor {
                selectedCategories.contains(.actors)
                    ? Destination(module: .value, itemID: stableID("\(document.id)#character-item"))
                    : nil
            } else if selectedCategories.contains(.rules), package.rulePackage == nil {
                Destination(module: .rule, itemID: stableID("\(document.id)#rule"))
            } else {
                selectedCategories.contains(.items)
                    ? Destination(module: .value, itemID: stableID("\(document.id)#item"))
                    : nil
            }
        case .scene where selectedCategories.contains(.scenes):
            Destination(module: .map, itemID: stableID("\(document.id)#map"))
        case .level where selectedCategories.contains(.scenes): Destination(
            module: .map,
            itemID: levelMapIDs[document.id] ?? stableID("\(document.id)#level-map")
        )
        case .journalEntry where selectedCategories.contains(.journals):
            Destination(module: .adventure, itemID: stableID("\(document.id)#journal"))
        case .journalEntryPage where selectedCategories.contains(.journals):
            document.parentID.map { Destination(module: .adventure, itemID: stableID("\($0)#journal")) }
        case .rollTable where selectedCategories.contains(.tables):
            Destination(module: .table, itemID: stableID("\(document.id)#table"))
        case .tableResult where selectedCategories.contains(.tables):
            document.parentID.map { Destination(module: .table, itemID: stableID("\($0)#table")) }
        case .playlist where selectedCategories.contains(.playlists):
            Destination(module: .audio, itemID: stableID("\(document.id)#playlist"))
        case .playlistSound where selectedCategories.contains(.playlists):
            document.parentID.map { Destination(module: .audio, itemID: stableID("\($0)#playlist")) }
        case .cards where selectedCategories.contains(.cards):
            Destination(module: .table, itemID: stableID("\(document.id)#cards"))
        case .card where selectedCategories.contains(.cards):
            document.parentID.map { Destination(module: .table, itemID: stableID("\($0)#cards")) }
        case .adventure where selectedCategories.contains(.adventures):
            Destination(module: .adventure, itemID: stableID("\(document.id)#adventure"))
        case .combat where selectedCategories.contains(.combats):
            Destination(module: .adventure, itemID: stableID("\(document.id)#combat"))
        case .combatant where selectedCategories.contains(.combats):
            document.parentID.map { Destination(module: .adventure, itemID: stableID("\($0)#combat")) }
        case .macro where selectedCategories.contains(.macros):
            Destination(module: .adventure, itemID: stableID("\(document.id)#macro"))
        default: nil
        }
    }

    func module(for path: String) -> NetworkModules? {
        if let plan = FoundryMediaNormalizer.plan(for: path) {
            return switch plan.kind {
            case .image: .photo
            case .audio: .audio
            }
        }
        return switch URL(filePath: canonicalResourcePath(path)).pathExtension.lowercased() {
        case "pdf": .pdf
        case "usdz": .space
        default: nil
        }
    }

    /// Canonical lookup keeps path case intact. Foundry packages can be authored on a
    /// case-sensitive file system, so a case-folded path is only safe as a secondary alias.
    func canonicalResourcePath(_ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        let noQuery = decoded.split(separator: "?", maxSplits: 1).first.map(String.init) ?? decoded
        return noQuery.split(separator: "#", maxSplits: 1).first
            .map(String.init)?
            .replacing("\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? ""
    }

    func resourceAlias(_ path: String) -> String {
        canonicalResourcePath(path).lowercased()
    }

    func actorCategory(_ subtype: String?) -> ItemListCategory {
        guard let subtype = subtype?.lowercased() else { return .monster }
        if subtype == "character" || subtype == "pc" || subtype.contains("player") { return .character }
        if subtype.contains("game") && subtype.contains("master") { return .gameMaster }
        return .monster
    }

    func tableCategory(_ document: FoundryDocument) -> ItemListCategory {
        let text = "\(document.name) \(document.subtype ?? "")".lowercased()
        return text.contains("loot") ? .loot : .generator
    }

    func foundryTags(_ document: FoundryDocument) -> [String] {
        ["Foundry VTT", document.subtype].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return FoundryTextDecoder.decodedText(value)
        }
    }

    func number(_ value: FoundryJSONValue?) -> Double? {
        switch value {
        case .integer(let value): Double(value)
        case .unsignedInteger(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }

    func firstValue(_ value: FoundryJSONValue, paths: [String]) -> FoundryJSONValue? {
        paths.lazy.compactMap { value.value(at: $0) }.first
    }

    func firstString(_ value: FoundryJSONValue, paths: [String]) -> String? {
        paths.lazy.compactMap { value.value(at: $0)?.stringValue }.first
    }

    func sanitizedFoundryText(_ optionalHTML: String?) -> String {
        FoundryTextDecoder.plainText(fromHTML: optionalHTML)
    }

    func safeText(_ optionalHTML: String?) -> String {
        rewriteFoundryLinks(sanitizedFoundryText(optionalHTML))
    }

    func decodedFoundryText(_ text: String?) -> String {
        guard let text else { return "" }
        return rewriteFoundryLinks(
            FoundryTextDecoder.decodedText(text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func prepareGenericRuleProjection(_ model: RuleModel, descriptionHTML: String?) {
        model.description = safeText(descriptionHTML)
        model.entries = model.entries.map { entry in
            var updated = entry
            updated.content = entry.kind == .value
                ? decodedFoundryText(entry.content)
                : safeText(entry.content)
            return updated
        }
    }

    func rewriteFoundryLinks(_ input: String) -> String {
        let linkTypes = [
            "UUID", "Actor", "Item", "Scene", "JournalEntry", "JournalEntryPage",
            "RollTable", "TableResult", "Playlist", "PlaylistSound", "Cards", "Card",
            "Adventure", "Combat", "Macro", "Compendium",
        ].joined(separator: "|")
        guard let expression = try? NSRegularExpression(
            pattern: #"@("# + linkTypes + #")\[([^\]\r\n]+)\](?:\{([^}\r\n]+)\})?"#
        ) else {
            return input
        }
        var output = input
        let matches = expression.matches(in: input, range: NSRange(input.startIndex..<input.endIndex, in: input))
        for match in matches.reversed() {
            guard let totalRange = Range(match.range(at: 0), in: output),
                  let typeRange = Range(match.range(at: 1), in: output),
                  let identifierRange = Range(match.range(at: 2), in: output) else { continue }
            let type = String(output[typeRange])
            let identifier = String(output[identifierRange])
            let candidates: [String] = switch type {
            case "UUID": [identifier]
            case "Compendium": [identifier, "Compendium.\(identifier)"]
            default: ["\(type).\(identifier)", identifier]
            }
            guard let destination = candidates.lazy.compactMap({ self.targetsByFoundryUUID[$0] }).first else { continue }
            let label: String
            if match.range(at: 3).location != NSNotFound, let labelRange = Range(match.range(at: 3), in: output) {
                label = String(output[labelRange])
            } else {
                label = identifier
            }
            output.replaceSubrange(totalRange, with: markdownLink(
                name: label,
                module: destination.module,
                itemID: destination.itemID
            ))
        }
        return output
    }

    func foundryReferenceAliases(for identifier: String) -> Set<String> {
        var aliases = Set([identifier])
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if components.first == "Compendium", components.count >= 5 {
            // Legacy @Compendium links omit both the Compendium prefix and document type.
            aliases.insert([components[1], components[2], components.last ?? ""].joined(separator: "."))
        }
        return aliases
    }

    func markdownLink(name: String, module: NetworkModules, itemID: UUID) -> String {
        let escapedName = name
            .replacing("\\", with: "\\\\")
            .replacing("[", with: "\\[")
            .replacing("]", with: "\\]")
            .replacing("\n", with: " ")
            .replacing("\r", with: " ")
        return "[\(escapedName)](\(URL.appScheme)://\(module.token)/0/\(itemID.uuidString))"
    }

    func inertCodeBlock(_ source: String) -> String {
        let longestBacktickRun = source.split(separator: "`", omittingEmptySubsequences: false)
            .dropLast()
            .reduce(0) { longest, _ in max(longest, 1) }
        // Four backticks safely contain normal triple-backtick source. If a future macro contains
        // a longer fence, extend the delimiter until it cannot terminate the block.
        var fenceLength = max(4, longestBacktickRun + 1)
        while source.contains(String(repeating: "`", count: fenceLength)) {
            fenceLength += 1
        }
        let fence = String(repeating: "`", count: fenceLength)
        return "\(fence)text\n\(source)\n\(fence)"
    }

    func displayString(_ value: FoundryJSONValue) -> String {
        switch value {
        case .object(let values):
            values.keys.sorted().compactMap { key in values[key].map { "\(key): \(displayString($0))" } }.joined(separator: ", ")
        case .array(let values): values.map(displayString).joined(separator: ", ")
        case .string(let value): value
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .number(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        case .null: "null"
        }
    }

    func presentedFoundryValue(_ value: FoundryJSONValue) -> String {
        switch value {
        case .object(let values):
            values.keys.sorted().compactMap { key in
                values[key].map {
                    "\(sanitizedFoundryText(key)): \(presentedFoundryValue($0))"
                }
            }.joined(separator: ", ")
        case .array(let values):
            values.map(presentedFoundryValue).joined(separator: ", ")
        case .string(let value):
            safeText(value)
        case .integer, .unsignedInteger, .number, .bool, .null:
            decodedFoundryText(displayString(value))
        }
    }

    func combatantSummary(_ combatant: FoundryDocument) -> String {
        let initiative = number(combatant.rawData["initiative"])
        let defeated = combatant.rawData["defeated"]?.boolValue ?? false
        let hidden = combatant.rawData["hidden"]?.boolValue ?? false
        return [
            initiative.map { "Initiative: \($0.formatted())" },
            "Defeated: \(defeated ? "yes" : "no")",
            "Hidden: \(hidden ? "yes" : "no")"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    func simpleModifier(_ formula: String) -> Double {
        let withoutDice = formula.replacing(/([0-9]*)[dD]([0-9]+)/, with: "")
        guard let expression = try? NSRegularExpression(pattern: #"[+-]\s*[0-9]+(?:\.[0-9]+)?"#) else {
            return 0
        }
        let matches = expression.matches(
            in: withoutDice,
            range: NSRange(withoutDice.startIndex..<withoutDice.endIndex, in: withoutDice)
        )
        return matches.compactMap { match in
            Range(match.range, in: withoutDice).flatMap {
                Double(withoutDice[$0].replacing(" ", with: ""))
            }
        }.reduce(0, +)
    }

    func base64Hash(_ hexadecimal: String) -> String? {
        guard hexadecimal.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let end = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index..<end], radix: 16) else { return nil }
            data.append(byte)
            index = end
        }
        return data.base64EncodedString()
    }
}
