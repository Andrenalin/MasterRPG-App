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

// MARK: - Indexes and folders

extension FoundryMappingState {
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
                warnings.append(String(localized: "Packaged resource path \(path) is duplicated and will not be attached automatically.", bundle: .module))
            }
        }
        for (alias, candidates) in aliasCandidates {
            try await cooperativeCheckpoint()
            if candidates.count == 1, let resource = candidates.first {
                resourcesByAlias[alias] = resource
            } else {
                ambiguousResourceAliases.insert(alias)
                warnings.append(String(localized: "Packaged resource alias \(alias) matches multiple files and will not be attached automatically.", bundle: .module))
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
                        itemId: stableID("rule#\(rule.id)")
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
                warnings.append(String(localized: "Actor id \(documentID) is ambiguous across Foundry collections; bare token links to it remain unresolved.", bundle: .module))
            }
        }
        for (alias, candidates) in destinationCandidates {
            try await cooperativeCheckpoint()
            if candidates.count == 1, let destination = candidates.first {
                targetsByFoundryUUID[alias] = destination
            } else {
                warnings.append(String(localized: "Foundry reference \(alias) is ambiguous across collections and remains unresolved.", bundle: .module))
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
        let declarationsByID = Dictionary(declarations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for folder in declarations {
            try await cooperativeCheckpoint()
            for module in modules(for: folder.documentType) {
                guard let id = resolveFolder(
                    module: module,
                    documentType: folder.documentType,
                    scope: folder.scope,
                    foundryID: folder.documentID
                ) else { continue }
                let parentID = cycleSafeParentID(for: folder, declarationsByID: declarationsByID).flatMap {
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
            warnings.append(String(localized: "Foundry folder id \(key.foundryID) is ambiguous across collections for \(key.module.token); only canonical in-collection links were resolved.", bundle: .module))
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

    /// Returns `folder.parentID` unless assigning it would create (or continue) a cycle in the
    /// projected `parentId` chain — mirroring `safeRuleFolderParent`'s cycle guard for the
    /// RuleRPG folder path, which this general module folder projection previously lacked.
    /// Without it, a Foundry folder cycle in the source data was silently projected as a
    /// genuine circular `parentId` chain, which any downstream code walking that chain upward
    /// (breadcrumbs, move/drag validation, folder deletion cascades) isn't guaranteed to be
    /// safe against. See CODE_AUDIT §5.13.
    func cycleSafeParentID(
        for folder: FolderDeclaration,
        declarationsByID: [String: FolderDeclaration]
    ) -> String? {
        guard let parentFoundryID = folder.parentID, !parentFoundryID.isEmpty else { return nil }
        var visited = Set([folder.id])
        var candidate: String? = parentFoundryID
        while let current = candidate {
            guard visited.insert(current).inserted else {
                warnings.append(String(localized: "Foundry folder hierarchy contains a cycle at \(folder.name); it was placed at the root.", bundle: .module))
                return nil
            }
            candidate = declarationsByID[current]?.parentID
        }
        return parentFoundryID
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

    func configureFolder<Model: AnyObject & ItemDataAccessible>(_ model: Model, name: String, parentID: UUID?) {
        var model = model
        model.name = name
        model.category = .folder
        model.parentId = parentID
    }
}
