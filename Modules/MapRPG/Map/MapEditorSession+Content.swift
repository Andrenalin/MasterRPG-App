// @copyright André Trettin

import CoreRPG
import SwiftUI

// Split out of MapEditorModel.swift — see CODE_AUDIT §9.13.

extension MapEditorSession {
    // MARK: - Pins Management

    func resetPlayerAndPins(newPins: [MapPinModel], map: MapModel, pinScale: CGFloat) {
        let modified = MapPinPlacement.displayPins(newPins, in: map, pinScale: pinScale)

        guard pins.mapPins != modified else { return }
        if mapMode == .edit {
            pins.mapPins = modified
        } else {
            withAnimation(.bouncy) {
                pins.mapPins = modified
            }
        }
    }

    // MARK: - Entries Management

    func resetEntries(
        newEntries: [MapEntryModel],
        map: MapModel,
        appliesFocus: Bool = true
    ) {
        let activeEntryId = editEntries.entries.first?.id

        // Merge incoming entries: prefer working-copy version for any entry that has
        // been locally edited (active edit entry and anything already flushed into entries).
        // Without a working copy (player and game master in game mode) nothing is looked up at
        // all; with one, both sides are indexed by id once instead of searched per incoming
        // entry. See CODE_AUDIT_26 §7.9.
        let workingEntriesById = workingCopy.map { copy in
            Dictionary(copy.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let localEntriesById = workingEntriesById == nil ? [:] : Dictionary(
            entries.entries.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let merged = newEntries.map { incoming -> MapEntryModel in
            // Active edit entry: keep what the user is working on, never overwrite with live
            if incoming.id == activeEntryId {
                return editEntries.entries.first ?? incoming
            }
            // Previously-edited entries reflected in display: keep local version if it differs
            // from the live map (it was flushed from editEntries and not yet committed).
            if let working = workingEntriesById?[incoming.id], working != incoming,
               let local = localEntriesById[incoming.id] {
                return local
            }
            return incoming
        }

        // Preserve hex entries that were generated into the working copy but don't exist in
        // the live map yet (they only reach the store on checkmark). Skip in game mode —
        // the live map is the single source of truth, so stale local hex entries must not
        // be re-appended after the user toggles hex off.
        let hexToAppend: [MapEntryModel]
        if workingCopy != nil {
            let localHexEntries = entries.entries.filter { $0.isHexGrid }
            let mergedIds = Set(merged.map { $0.id })
            hexToAppend = localHexEntries.filter { !mergedIds.contains($0.id) }
        } else {
            hexToAppend = []
        }
        let final = merged + hexToAppend
        let previousEntryIds = Set(entries.entries.map(\.id))
        let finalEntryIds = Set(final.map(\.id))
        let isInitialRoomHydration = awaitingInitialRoomHydration
            && previousEntryIds != finalEntryIds
        if isInitialRoomHydration {
            awaitingInitialRoomHydration = false
        }

        // Seed persisted focus regardless of whether game-mode entries were
        // already installed at session creation. Initial synchronization keeps
        // the focus value but deliberately does not zoom to it. The same rule
        // applies when room records arrive after the initially empty map has
        // already fitted. Once that structural hydration completes, focus-only
        // updates for the same room identities resume normal game semantics.
        let focus = final.first(where: { $0.focused })?.id
        let focusChanged = focus != focusId
        if focusChanged {
            focusId = focus
        }

        if entries.entries != final {
            withAnimation(.bouncy) {
                entries.resetEntries(mapId: map.id, entries: final)
            }
        }
        isHexMap = final.contains(where: { $0.isHexGrid })

        if focusChanged, appliesFocus, appeared, !isInitialRoomHydration {
            focusedMap()
        }
    }

    // MARK: - Change Management (view state only — no save)

    func changeImage(map: MapModel) {
        let changedMap = mapId != map.id
        mapId = map.id
        hexScale = map.hexMapScale
        pinScale = map.pinScale
        isHexMap = map.entries.contains(where: { $0.isHexGrid })
        resetReshare()

        if changedMap {
            appeared = false
            pendingInitialFitMapId = map.id
            awaitingInitialRoomHydration = false
            focusId = nil
            workingCopy = nil
            clearSelections()
            if mapMode == .edit {
                pins.mapPins = map.mapPins
                history.reset(to: MapEditorSnapshot(map: map, activeEntryId: nil))
            } else {
                pins.mapPins = map.mapPins
            }
            pins.pointer = map.pointer
            rooms.reset(
                mapId: map.id,
                passiveEntries: mapMode == .edit ? [] : map.entries
            )
            // Content identity is part of viewport state. Reset even when the
            // replacement map happens to have the same image dimensions.
            viewport.configure(makeViewportConfiguration())
        }
        changeMap(map: map)
    }

    func changeMap(map: MapModel) {
        editEntries.needleInteraction.dragCoordinate = nil
        clearSelections()

        if appeared {
            resetZoom()
        }
    }

    // MARK: - First Appear

    func firstAppear(map: MapModel) {
        guard mapId == map.id else { return }
        presentationIsActive = true
        appeared = false
        pendingInitialFitMapId = map.id
        resetEntries(newEntries: map.entries, map: map, appliesFocus: false)
        awaitingInitialRoomHydration = entries.entries.isEmpty
        _ = completePendingInitialFitIfPossible()
    }

    func disappear() {
        presentationIsActive = false
        appeared = false
        editEntries.needleInteraction.dragCoordinate = nil
    }

    // MARK: - Helper Methods

    /// The topmost room under `location`. The cells of a hex grid are appended last and cover the
    /// whole map, so they are skipped: a pin dropped on a hex map belongs to the room it sits in,
    /// and a cell would lose its content on the next rescale. See CODE_AUDIT_26 §5.22.
    func entry(for location: CGPoint, in _: MapModel) -> MapEntryModel? {
        entries.roomNodes.last { !$0.entry.isHexGrid && $0.path.contains(location) }?.entry
    }

    // MARK: - Pointer (game mode)

    func resetPointer(map: MapModel) {
        guard pins.pointer != map.pointer else { return }
        if appeared {
            withAnimation(.bouncy) { pins.pointer = map.pointer }
        } else {
            pins.pointer = map.pointer
        }
    }

    func updatePointer(location: CGPoint, map: MapModel, withOutRelocation: Bool = false) {
        guard map.pointer.isShown || isPointing else { return }
        if mapMode == .gameMaster {
            map.pointer.isShown = isPointing
        }
        if withOutRelocation {
            map.pointer.location = location
        } else {
            map.pointer.location = contentPoint(fromViewport: location)
        }
        map.pointer.timeInterval = GameController.bumpedTimeInterval(from: map.pointer.timeInterval)
        pins.setPinPointer(updatedPin: map.pointer)
        broadcastMapEdit()
    }

    // MARK: - Broadcasting (game mode)

    /// Sends a game-master edit (room, pin, pointer) to the players unless the game master paused
    /// sharing (`isStreaming`) — the 2D counterpart of the 3D table's `broadcastMapEdit(for:)`, so
    /// both honour the same "Share Map" toggle. Every edit-driven send must go through here (or
    /// `broadcastFocusEdit()`); only the toolbar's explicit sends (`sendMapUpdates()`, "Refresh
    /// Shared Map") bypass the pause. A player's own pin/pointer updates are never paused.
    func broadcastMapEdit() {
        guard sharesEdits else { return }
        actions.sendMapUpdates?()
    }

    /// `broadcastMapEdit()` for a room focus change, which is sent through its own action.
    func broadcastFocusEdit() {
        guard sharesEdits else { return }
        actions.focused?()
    }

    private var sharesEdits: Bool {
        mapMode != .gameMaster || isStreaming
    }
}
