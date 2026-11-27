// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
#if !os(tvOS)
import GeneratorRPG
#endif
import PhotoRPG
import SwiftUI

// The monster, photo-pin and hex-grid edits, split out of EditController.swift. See CODE_AUDIT_29 §9.9.

extension EditController {
    @MainActor func add(pin: MapPinModel, at index: Int? = nil, to model: MapModel) {
        let validatedIndex: Int
        if let index {
            validatedIndex = min(max(0, index), model.mapPins.count)
        } else {
            validatedIndex = model.mapPins.count
        }
        model.mapPins.insert(pin, at: validatedIndex)
        save(updated: model, message: String(localized: "Added pin", bundle: .module))
    }

}

extension EditController {
    @MainActor func addMonsters(map: MapModel, entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int) {
        addMonsters(to: map, entryId: entryId, location: location, monsters: monsters, number: number)
    }

    @MainActor private func addMonsters(to model: MapModel, entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int) {
        guard appendMonsters(to: model, entryId: entryId, location: location, monsters: monsters, number: number) else { return }
        save(updated: model, message: String(localized: "Added pin", bundle: .module))
    }

    /// Adds the monster pins without saving. `false` when there were none.
    @discardableResult
    @MainActor func appendMonsters(to model: MapModel, entryId: UUID?, location: CGPoint?, monsters: [ItemRowModel], number: Int) -> Bool {
        var pins = MapPinPlacement.spawnPins(monsters: monsters, count: number, location: location, characterRoot: root.characterRoot)

        if let entryId, location == nil {
            pins = MapPinPlacement.cascade(pins: pins, in: model[entryId], pinScale: model.pinScale)
        }
        // All pins are appended first and saved once: one save (and one broadcast) per pin
        // made adding a group of monsters N saves. See CODE_AUDIT_26 §7.56.
        guard !pins.isEmpty else { return false }
        model.mapPins.append(contentsOf: pins)
        return true
    }
}

extension EditController {
    /// Adds one pin per photo to a game map, named after the photo and linked to no character.
    /// At `location` when given, otherwise cascaded in `entryId`'s room.
    @MainActor func addPhotoPins(map: MapModel, entryId: UUID?, location: CGPoint?, photoIds: [UUID]) {
        guard !photoIds.isEmpty else { return }
        let photos = photoIds.map { (photoId: $0, name: root.photoRoot.itemControllable.nameSync(itemId: $0)) }
        var pins = MapPinPlacement.spawnPhotoPins(photos: photos, location: location)
        if let entryId, location == nil {
            pins = MapPinPlacement.cascade(pins: pins, in: map[entryId], pinScale: map.pinScale)
        }
        map.mapPins.append(contentsOf: pins)
        save(updated: map, message: String(localized: "Added pin", bundle: .module))
    }
}
