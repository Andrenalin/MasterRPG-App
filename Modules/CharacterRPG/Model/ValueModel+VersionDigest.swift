// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Version Digest
// Split out of ValueModel.swift — see CODE_AUDIT_Character §9.9.

extension ValueModel {
    /// Deterministic identity of the Character content exchanged during game
    /// setup. Linked asset identifiers are part of the Character, but their
    /// bytes, device-local availability, list hierarchy, and UI state are
    /// deliberately not represented.
    public var version: Int {
        StableVersionDigest.digest(CanonicalValueContent(self))
    }
}

private struct CanonicalValueContent: Codable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let tags: [String]
    let category: ItemListCategory
    let photoId: UUID?
    let photos: [UUID]
    let entries: [CanonicalValueEntry]
    let diceId: UUID?

    @MainActor
    init(_ model: ValueModel) {
        // Imports migrate a legacy Character category to `.entry` and add a
        // localized category tag. Recover that semantic category and remove
        // exactly the generated tag so pre- and post-import models fingerprint
        // identically while genuine user tags (including duplicates) remain.
        let (canonicalCategory, canonicalTags) = Self.categoryAndTags(for: model)

        id = model.id
        name = model.name
        description = model.description
        tags = canonicalTags
        category = canonicalCategory
        photoId = model.photoId
        photos = model.photos
        entries = model.entries.map(CanonicalValueEntry.init)
        diceId = model.diceId
    }

    @MainActor
    private static func categoryAndTags(for model: ValueModel) -> (ItemListCategory, [String]) {
        var category = model.category
        var tags = model.tags

        if category == .entry {
            for legacyCategory in ItemListCategory.characterPackageCategories {
                let localizedTags = legacyCategory.allLocalizedTitles
                guard let index = tags.firstIndex(where: localizedTags.contains) else { continue }
                category = legacyCategory
                tags.remove(at: index)
                break
            }
        }

        // Tags are semantically unordered. `String.<` is locale-independent,
        // unlike the localized ordering used by the persistence migration.
        return (category, tags.sorted())
    }
}

private extension ItemListCategory {
    static let characterPackageCategories: [ItemListCategory] = [
        .character,
        .gameMaster,
        .item,
        .monster,
    ]

    @MainActor
    var allLocalizedTitles: Set<String> {
        var resource = localizedTitle
        var localizationIdentifiers = [resource.locale.identifier, "en"]

        let resourceBundle: Bundle? = switch resource.bundle {
        case .main:
            .main
        case let .forClass(bundleClass):
            Bundle(for: bundleClass)
        case let .atURL(url):
            Bundle(url: url)
        @unknown default:
            nil
        }
        localizationIdentifiers.append(contentsOf: resourceBundle?.localizations ?? [])

        return Set(localizationIdentifiers.map { identifier in
            resource.locale = Locale(identifier: identifier)
            return String(localized: resource)
        })
    }
}

private struct CanonicalValueEntry: Codable, Sendable {
    let id: UUID
    let name: String
    let type: ValueEntryModel.ValueType
    let isGenerator: Bool
    let value: String
    let diceId: UUID?
    let valueId: UUID?

    init(_ entry: ValueEntryModel) {
        id = entry.id
        name = entry.name
        type = entry.type
        isGenerator = entry.isGenerator
        value = entry.value
        diceId = entry.diceId
        valueId = entry.valueId
    }
}
