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

// MARK: - Assets

extension FoundryMappingState {
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
        return markdownLink(name: name, module: module, itemId: id)
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
