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
        if let existing = resourceIds[key] {
            if let first = resourceSources[key], first != resource {
                warnings.append(String(localized: "Packaged resources \(first.logicalPath) and \(resource.logicalPath) have the same path and only the first was imported.", bundle: .module))
            }
            return existing
        }
        resourceSources[key] = resource
        let id = stableId("asset#\(module.token)#\(key.path)")
        resourceIds[key] = id
        let sourceFilename = resource.logicalPath.split(separator: "/").last.map(String.init)
            ?? resource.logicalPath
        let expectedMediaKind: FoundryMediaNormalizationPlan.Kind? = switch module {
        case .photo: .image
        case .audio: .audio
        default: nil
        }
        let normalizationPlan = FoundryMediaNormalizer.plan(
            forPackagedPath: resource.logicalPath,
            expectedKind: expectedMediaKind
        )
        let filename = normalizationPlan?.suggestedFilename
            ?? FoundryTextDecoder.decodedText(sourceFilename)
        let attachment: ExternalImportAttachment
        if module == .photo || module == .audio {
            guard let normalizationPlan else {
                warnings.append(String(localized: "Foundry media \(resource.logicalPath) has no safe raster or audio conversion and was not projected.", bundle: .module))
                return id
            }
            attachment = ExternalImportAttachment(
                id: id,
                fileId: id,
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
                fileId: id,
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
            add(model, module: module, sourceId: "asset:\(resource.logicalPath)", attachment: attachment)
        case .audio:
            let model = AudioModel.empty(id)
            configureAsset(model, name: filename, category: .music)
            add(model, module: module, sourceId: "asset:\(resource.logicalPath)", attachment: attachment)
        case .pdf:
            let model = PdfModel.empty(id)
            configureAsset(model, name: filename, category: .pdf)
            add(model, module: module, sourceId: "asset:\(resource.logicalPath)", attachment: attachment)
        case .space:
            let model = SpaceModel.empty(id)
            configureAsset(model, name: filename, category: .models)
            add(model, module: module, sourceId: "asset:\(resource.logicalPath)", attachment: attachment)
        default:
            break
        }
        return id
    }

    func configureAsset<Model: AnyObject & ItemDataAccessible>(_ model: Model, name: String, category: ItemListCategory) {
        var model = model
        model.name = name
        model.description = "Imported from \(packageName)."
        model.category = category
        model.tags = ["Foundry VTT"]
    }

    func mediaId(path: String?, module: NetworkModules) -> UUID? {
        guard selectedCategories.contains(.assets),
              let path,
              let resource = resource(matching: path),
              resource.location == .packaged else {
            return nil
        }
        let contextualPlan = FoundryMediaNormalizer.plan(
            forPackagedPath: resource.logicalPath,
            expectedKind: module == .audio ? .audio : nil
        )
        guard self.module(for: resource.logicalPath) == module
            || (module == .audio && contextualPlan?.kind == .audio) else {
            warnings.append(String(localized: "Foundry media reference \(path) is not a \(module.token) resource and was not projected into that module.", bundle: .module))
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
        let name = FoundryMediaNormalizer.plan(forPackagedPath: resource.logicalPath)?.suggestedFilename
            ?? resource.logicalPath.split(separator: "/").last.map {
                FoundryTextDecoder.decodedText(String($0))
            }
            ?? FoundryTextDecoder.decodedText(resource.logicalPath)
        return markdownLink(name: name, module: module, itemId: id)
    }

    /// The packaged resource a document reference points to. A reference can be a URL, so
    /// `Token%20%231.webp?v=2` finds `Token #1.webp`; an unencoded `Token #1.webp` is tried as a
    /// whole first, because the `#` is then part of the name and not a fragment.
    func resource(matching path: String) -> FoundryPackageResource? {
        for (canonicalPath, alias) in [
            (canonicalResourcePath(path), resourceAlias(path)),
            (canonicalReferencePath(path), referenceAlias(path)),
        ] {
            if let exact = resourcesByCanonicalPath[canonicalPath] {
                return exact
            }
            if ambiguousResourceCanonicalPaths.contains(canonicalPath) {
                return nil
            }
            if let resource = resourcesByAlias[alias] {
                return resource
            }
            if ambiguousResourceAliases.contains(alias) {
                return nil
            }
        }
        return nil
    }
}
