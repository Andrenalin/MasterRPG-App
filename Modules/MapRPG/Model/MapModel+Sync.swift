// @copyright André Trettin

import CoreRPG
import Foundation

// Split out of MapModel.swift — see CODE_AUDIT §9.13.

// `Comparable`, `ItemDiffComparable`, `Equatable`, and `Hashable` below are
// declared `nonisolated` so `MapModel` can sit in a `Set`/`Dictionary` or be
// `.sorted()` without forcing every call site onto `@MainActor`, but their
// bodies reach this @MainActor-isolated class's stored properties through
// `assumeMainActorIsolated` — a runtime trust-the-caller check, not a
// compile-time one. A call from off-`MainActor` compiles cleanly and traps at
// runtime instead. Every call site in this module (and the wider app, per a
// full-module audit) is already `@MainActor`-only, so this is a deliberate,
// repo-wide trade-off (all module models use this pattern), not a bug — but
// it's worth knowing before adding a new caller. See CODE_AUDIT §3.2.
extension MapModel: nonisolated Comparable {
    nonisolated public static func < (lhs: MapModel, rhs: MapModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.name < rhs.name

        }
    }
}

extension MapModel: nonisolated ItemLinkRegistrable {
    @MainActor public var linkRegisterModels: [LinkRegisterModel] {
        changedLinkRegisterModels(oldValue: .empty).0
    }

    @MainActor public func changedLinkRegisterModels(oldValue: MapModel) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []

        let oldPinIds = Set(oldValue.mapPins.compactMap(\.photoId))
        let newPinIds = Set(mapPins.compactMap(\.photoId))

        if oldPinIds != newPinIds {
            let modelSource = ItemRowModel(itemId: id, typeId: .value)
            let addedPhotos = newPinIds.subtracting(oldPinIds)
            let removedPhotos = oldPinIds.subtracting(newPinIds)
            addedPhotos.forEach {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo)))
            }
            removedPhotos.forEach {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo)))
            }
        }

        if oldValue.photoId != photoId {
            let modelSource = ItemRowModel(itemId: id, typeId: .map)
            if let photoId {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: photoId, typeId: .photo)))
            }
            if let oldPhotoId = oldValue.photoId {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: oldPhotoId, typeId: .photo)))
            }
        }

        if oldValue.entries != entries {
            let addedEntryIds = Set(entries.map(\.id)).subtracting(Set(oldValue.entries.map(\.id)))
            let removedEntryIds = Set(oldValue.entries.map(\.id)).subtracting(Set(entries.map(\.id)))
            addedEntryIds.forEach {
                added.append(contentsOf: linkRegisterModels(entry: self[$0]))
            }
            removedEntryIds.forEach {
                removed.append(contentsOf: linkRegisterModels(entry: oldValue[$0]))
            }
            let sameEntryIds = Set(entries.map(\.id)).intersection(Set(oldValue.entries.map(\.id)))
            sameEntryIds.forEach {
                let oldEntry = oldValue[$0]
                let newEntry = self[$0]
                if oldEntry != newEntry {
                    removed.append(contentsOf: linkRegisterModels(entry: oldEntry, valueChanged: oldEntry.content != newEntry.content))
                    added.append(contentsOf: linkRegisterModels(entry: newEntry, valueChanged: oldEntry.content != newEntry.content))
                }
            }
        }

        return (added, removed)
    }

    @MainActor func linkRegisterModels(entry: MapEntryModel, valueChanged: Bool = true) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .map)
        var total: [LinkRegisterModel] = []
        if valueChanged {
            total += LinkReplaceController.links(for: entry.content).map {
                LinkRegisterModel(link: $0, source: source)
            }
        }
        return total
    }
}

extension MapModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: MapModel) -> MapModel {
        return assumeMainActorIsolated {
            let mergedPhotoId = photoId_.merged(other: other.photoId_)
            let mergedMapPins = mapPins_.merged(other: other.mapPins_)
            let mergedWalls = walls_.merged(other: other.walls_)
            let mergedCategory = category_.merged(other: other.category_)
            let mergedEntries: CRDTDataUpdate<[MapEntryModel]>
            if mergedCategory.wrappedValue == .folder {
                // Deterministic union (name, then id). See CODE_AUDIT_18 §9.9.
                let combined = FolderEntryMerge.merged(local: entries, remote: other.entries, id: \.id, name: \.name)
                mergedEntries = CRDTDataUpdate(wrappedValue: combined)
            } else {
                mergedEntries = entries_.merged(other: other.entries_)
            }
            return MapModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                entries: mergedEntries,
                displayConfig: displayConfig_.merged(other: other.displayConfig_),
                photoId: mergedPhotoId,
                width: mergedPhotoId.update == photoId_.update ? width : other.width,
                height: mergedPhotoId.update == photoId_.update ? height : other.height,
                mapPins: mergedMapPins,
                walls: mergedWalls,
                // Was always `pinScale` (self), silently discarding the
                // peer's incoming change on every merge conflict — every
                // other persisted scalar field here is arbitrated one way
                // or another, this one wasn't. See CODE_AUDIT_13 §5.3.
                pinScale: other.pinScale,
                hexMapScale: hexMapScale_.merged(other: other.hexMapScale_),
                scale: other.scale,
                degrees: other.degrees,
                parentId: other.parentId
            )

        }
    }

    nonisolated public func isSame(_ other: MapModel) -> Bool {
        return assumeMainActorIsolated {
            // Split comparison into typed chunks for faster type-checking
            let basicFieldsMatch: Bool = (
                name == other.name &&
                description == other.description &&
                tags == other.tags &&
                category == other.category
            )
            guard basicFieldsMatch else { return false }

            let configMatch: Bool = (
                displayState == other.displayState &&
                entries_.update == other.entries_.update &&
                displayConfig == other.displayConfig &&
                photoId_.update == other.photoId_.update &&
                width == other.width &&
                height == other.height &&
                mapPins_.update == other.mapPins_.update &&
                walls_.update == other.walls_.update &&
                hexMapScale == other.hexMapScale &&
                pinScale == other.pinScale &&
                scale == other.scale &&
                degrees == other.degrees &&
                parentId == other.parentId
            )
            guard configMatch else { return false }

            // Sanity checks
            guard entries.count == other.entries.count else { return false }
            let entriesMatch: Bool = entries.enumerated().allSatisfy { index, entry in
                entry == other.entries[index]
            }
            guard entriesMatch else { return false }

            guard mapPins.count == other.mapPins.count else { return false }
            let pinsMatch: Bool = mapPins.enumerated().allSatisfy { index, pin in
                pin == other.mapPins[index]
            }
            guard pinsMatch else { return false }

            guard walls.count == other.walls.count else { return false }
            return walls.enumerated().allSatisfy { index, wall in
                wall == other.walls[index]
            }

        }
    }

    public var version: Int {
        // Must be identical across processes and devices: the master sends this
        // version with a reveal reference, and a player re-requests the full map
        // payload whenever its local value differs. `hashValue` is randomly
        // seeded per launch, so it forced a full re-transfer on every reveal.
        Int(bitPattern: UInt(truncatingIfNeeded: Double(hexMapScale + pinScale).bitPattern))
    }
}
