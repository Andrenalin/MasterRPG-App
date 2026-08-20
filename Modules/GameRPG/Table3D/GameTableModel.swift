// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import RealityKit
import SwiftUI
import os.log

#if os(visionOS)
import DiceRPG
import TabletopKit
#endif

@Observable @MainActor
final class GameTableModel: Sendable {
    let renderer: GameRenderer
    let setup: GameSetup

#if os(visionOS)
    let tabletopGame: TabletopGame
    let observer: GameObserver
#endif

    // References to root models for accessing game controllers.
    let mapRoot: MapRootModel
    let photoRoot: PhotoRootModel

    var currentMapId: UUID?
    var currentMapImage: AKImage?
    var currentMapDegrees: Double = 0
    var networkActions: NetworkActions?
    var isGameMaster = false

    // MARK: - Shared toolbar state (`GameToolBarSession`)

    /// Defaults to true: the volumetric table is inherently already shared
    /// once it's open (unlike the 2D map, there's no private-editing mode to
    /// opt out of), but the game master can still pause broadcasting
    /// toolbar-driven edits (added pins, pointer moves) if they want to.
    var isStreaming = true
    /// Local GM preview of how the board reads in another role, same as the
    /// 2D map's display mode. Purely a rendering lens — it never changes
    /// what's actually shared; see `renderIsGameMaster`.
    var displayMode: MapDisplayMode = .master {
        didSet {
            guard oldValue != displayMode else { return }
            replaceFogOfWarTask(isGameMaster: isGameMaster)
        }
    }
    private var lastPinScale: CGFloat = 1
    private var lastHexScale: Double = 0
    private var lastIsHexMap: Bool = false

    /// The local player's own pin id (== the player's game id); nil on the master.
    var playerPinId: UUID?
    /// Set by `assignSeatsForSharePlay` (see `GameEquipment.swift`) to the
    /// total player count whenever the party has more players than the
    /// table has non-master seats (currently 2; the 4th table side is
    /// reserved for the shared die/deck, not a seat) — meaning this device's
    /// seat, and the seat's 2 `Die20` equipment ids, may be shared with
    /// another player. `nil` when every player has an exclusive seat.
    /// Deliberately not a precise "shared with N others" count: which
    /// specific players share a seat can't be determined locally (SharePlay
    /// participants carry no host/role marker to exclude the master from
    /// the ranking — see the method's doc comment), only that sharing is
    /// happening somewhere. See CODE_AUDIT §5.2.
    var sharedSeatPlayerCount: Int?
    /// The game master's local menu selection. Highlighting is intentionally
    /// not represented here because multiple shared pins may be highlighted.
    private(set) var selectedPinId: UUID?
    private(set) var selectedPin: MapPinModel?
    private var pinMenuAttachment: Entity?
    /// Resolved once per drag gesture by `pinDragChanged(pinId:position:)` and cleared by
    /// `pinDragEnded(pinId:position:)`, so the per-tick drag path doesn't re-scan `pinPawns` on
    /// every delta. See CODE_AUDIT §7.3.
    private var cachedDragPawn: (pinId: UUID, pawn: PinPawn)?
    private var currentPhotoId: UUID?
    private var currentPhotoVersion: Int?
    private var pendingPinPhotoIds: [UUID: UUID] = [:]
    /// Tracks the `Task` spawned per pin by `syncPawnsWithMapPins()` so a
    /// pin whose photo load is superseded (or the whole model torn down) can
    /// have its in-flight load cancelled instead of running to completion
    /// with no one left to apply the result. See CODE_AUDIT §3.5.
    private var pendingThumbnailTasks: [UUID: Task<Void?, Never>] = [:]
    /// Tracks the in-flight `updateFogOfWar` `Task`, created and replaced only through
    /// `replaceFogOfWarTask(isGameMaster:)` so every fog-affecting entry point — a
    /// continuous drag (`panViewport(by:)`), `displayMode`'s `didSet`, room toggle/focus,
    /// "show/hide all", and a map change — shares one cancel-then-replace point instead of
    /// racing each other with independently-awaited direct calls. See CODE_AUDIT §5.5/§3.3.
    private var fogOfWarTask: Task<Void, Never>?
    /// Signature of every value that affects the rendered board texture.
    /// Pin-only mapState messages can then skip a full fog recomposite.
    private var fogSignature: Int?

    /// A local, per-client pan applied on top of `boardFocusRect`'s
    /// room-centered crop — dragging the map surface while a room is
    /// focused/zoomed adjusts this instead of moving anything in 3D space
    /// (see `GameTableView.viewportPanGesture`) or touching map data. Not
    /// networked: each client frames their own zoomed view independently,
    /// same as the 2D map's viewport is per-client.
    var manualViewportOffset: CGPoint = .zero
    /// The room id `manualViewportOffset` was last computed against. A stale
    /// pan (from before a *different* room was focused, or before focus
    /// cleared) could point outside the new crop entirely, so it resets
    /// whenever this changes — including a focus change that arrived over
    /// the network, not just ones this client made.
    private var lastFocusedRoomId: UUID?

    @MainActor
    init(mapRoot: MapRootModel, photoRoot: PhotoRootModel) {
        self.mapRoot = mapRoot
        self.photoRoot = photoRoot

        renderer = GameRenderer()
        setup = GameSetup(root: renderer.root)

#if os(visionOS)
        tabletopGame = TabletopGame(tableSetup: setup.setup)
        observer = GameObserver(tabletop: tabletopGame, renderer: renderer)
        tabletopGame.addObserver(observer)
        tabletopGame.addRenderDelegate(renderer)
#endif

        renderer.game = self
        resetGame()
    }

#if os(visionOS)
    // MARK: - Seating & Space Setup

    /// Called when the 3D table view appears to set up seating.
    func setupSeating(sharePlayController: RPGSharePlayController) {
        let isMaster = sharePlayController.gameModel?.gameConfig.isMaster ?? false
        observer.isMaster = isMaster
        if sharePlayController.isActive, let groupSession = sharePlayController.groupSession {
            Logger.sharePlay.debug("Setting up seating with SharePlay")
            assignSeatsForSharePlay(groupSession: groupSession, isMaster: isMaster)
            sharePlayController.setupSeatAssignment(gameTableModel: self)
        } else {
            Logger.sharePlay.debug("Setting up seating for single-player")
            tabletopGame.claimAnySeat()
        }
        // `GameObserver.playerChangedSeats` keeps this current for every
        // later seat change (players joining/leaving SharePlay); this call
        // covers the gap between the claim(s) above and that callback's
        // first firing, so no seat's dice flash visible before its claim
        // is reflected.
        tabletopGame.withCurrentSnapshot { snapshot in
            updateDiceVisibility(using: snapshot)
        }
    }

    /// Shows a die only once two conditions both hold: its seat is actually
    /// claimed (a player, or the master for seat 0), and the die itself is
    /// currently part of that seat's focused dice set — tracked via the
    /// die's own synced `value`, using `0` as this table's own sentinel for
    /// "not part of the current set" (see `GameSetup.maxDicePerType`, and
    /// the matching guard in `Die20`/`Die.restingOrientation`). Every seat
    /// pre-allocates a full pool of both types up front (TabletopKit
    /// equipment can't be added once `TableSetup` is frozen) —
    /// `applyDiceRoll` claims exactly as many of each type as the locally
    /// focused dice model needs by giving them a real value, and this
    /// method is what turns that synced value into actual visibility for
    /// every participant. Driven by `GameObserver.playerChangedSeats` (seat
    /// occupancy changed) and `GameObserver.actionWasConfirmed` (a die's
    /// value changed), both of which already receive a fresh `TableSnapshot`.
    func updateDiceVisibility(using snapshot: TableSnapshot) {
        for (seatId, dieIds) in setup.playerD20Ids {
            let isOccupied = (snapshot.state(matching: seatId) as? TableSeatState)?.playerID != nil
            for dieId in dieIds {
                guard let (die20, state) = snapshot.equipment(of: Die20.self, matching: dieId) else { continue }
                die20.entity.isEnabled = isOccupied && state.value != 0
            }
        }
        for (seatId, dieIds) in setup.playerD6Ids {
            let isOccupied = (snapshot.state(matching: seatId) as? TableSeatState)?.playerID != nil
            for dieId in dieIds {
                guard let (die, state) = snapshot.equipment(of: Die.self, matching: dieId) else { continue }
                die.entity.isEnabled = isOccupied && state.value != 0
            }
        }
    }

    /// This device's own seat, however it was claimed (SharePlay assignment
    /// or `claimAnySeat()` for local/single-player) — queried directly from
    /// TabletopKit's synchronized seat state rather than tracked separately
    /// during assignment, so it stays correct even if seating changes later.
    private var localSeat: TableSeatIdentifier? {
        var result: TableSeatIdentifier?
        tabletopGame.withCurrentSnapshot { snapshot in
            result = snapshot.seat(of: PlayerSeat.self, for: tabletopGame.localPlayer)?.0.id
        }
        return result
    }

    /// Set by `applyDiceRoll` whenever the locally focused dice set has more
    /// dice of a type than this seat has table slots for (currently
    /// `GameSetup.maxDicePerType`, 6, per type — see `playerD20Ids`/
    /// `playerD6Ids`), or dice of a type the table has no mesh for at all
    /// (only d20 and d6 are supported); `nil` when the last set mirrored
    /// entirely. The count of dice that could not be mirrored onto the
    /// table, so `GameTableView` can surface a "N results not shown on
    /// table" notice instead of the drop being silent. See CODE_AUDIT §5.1.
    private(set) var diceOverflowCount: Int?

    // MARK: - Dice

    /// Mirrors the locally focused character-sheet dice set onto the local
    /// player's own seat — showing exactly as many `Die20`/`Die` (d6) slots
    /// as the set needs of each type, typed and positioned to match (a mix
    /// of both is fine), and parking every other slot in this seat's pool
    /// back at the hidden `0` sentinel (see `updateDiceVisibility(using:)`).
    /// Reuses DiceRPG's existing focus-dice mechanism as the trigger (see
    /// `GameTableView`'s observer) rather than building a new, separate
    /// notion of "selected dice" for the table. `TabletopGame.addAction`
    /// syncs every change — including which slots are active — to every
    /// other participant automatically, the same way a physical toss
    /// already does, so every device ends up showing the same shape for
    /// this seat.
    ///
    /// Only d20 and d6 are backed by a table mesh, and each seat only has
    /// `GameSetup.maxDicePerType` slots per type; a set with dice of any
    /// other side count, or more than that many of one type (a homebrew
    /// "roll 8d6", or a GM batch-rolling for multiple NPCs at once), has the
    /// extras dropped rather than mirrored. See CODE_AUDIT §5.1 — this is
    /// surfaced via `diceOverflowCount` and a log, rather than silently
    /// discarded as before.
    func applyDiceRoll(_ diceModel: DiceModel) {
        guard let seat = localSeat,
              let d20Ids = setup.playerD20Ids[seat],
              let d6Ids = setup.playerD6Ids[seat],
              let seatPose = setup.seats.first(where: { $0.id == seat })?.initialState.pose
        else { return }

        // Compare the *resolved* side count (`RawDie.max`, public), not the
        // `Sides` enum case directly — a die authored through the sheet's
        // own UI can end up as `.number(20)` instead of the dedicated
        // `.twenty` case, and those don't compare equal to each other
        // despite meaning the same die.
        let d20Dice = diceModel.dice.filter { $0.die.max == 20 }
        let d6Dice = diceModel.dice.filter { $0.die.max == 6 }
        let usedD20Count = min(d20Dice.count, d20Ids.count)
        let usedD6Count = min(d6Dice.count, d6Ids.count)
        let layout = PlayerSeat.diceLayout(inFrontOf: seatPose, count: usedD20Count + usedD6Count)

        for (index, dieId) in d20Ids.enumerated() {
            guard let equipment = tabletopGame.equipment(of: Die20.self, matching: dieId) else { continue }
            if index < usedD20Count {
                let result = d20Dice[index].result.last ?? 1
                tabletopGame.addAction(
                    .updateEquipment(equipment, value: result, seatControl: nil, pose: layout[index], boundingBox: nil, context: 0)
                )
            } else {
                tabletopGame.addAction(
                    .updateEquipment(equipment, value: 0, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
                )
            }
        }

        for (index, dieId) in d6Ids.enumerated() {
            guard let equipment = tabletopGame.equipment(of: Die.self, matching: dieId) else { continue }
            if index < usedD6Count {
                let result = d6Dice[index].result.last ?? 1
                tabletopGame.addAction(
                    .updateEquipment(equipment, value: result, seatControl: nil, pose: layout[usedD20Count + index], boundingBox: nil, context: 0)
                )
            } else {
                tabletopGame.addAction(
                    .updateEquipment(equipment, value: 0, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
                )
            }
        }

        let overflowCount = diceModel.dice.count - usedD20Count - usedD6Count
        diceOverflowCount = overflowCount > 0 ? overflowCount : nil
        if overflowCount > 0 {
            Logger.gameTable.warning(
                "Focused dice set had \(overflowCount, privacy: .public) dice this table couldn't represent (unsupported sides, or more than \(GameSetup.maxDicePerType, privacy: .public) of one type at this seat); those results were not mirrored onto the table"
            )
        }
    }

    /// VoiceOver's "activate" gesture on a die entity (see `DiceComponent`,
    /// wired in `GameTableView`'s accessibility subscription) — the direct
    /// on-table toss gesture otherwise has no accessible equivalent. Picks a
    /// random result and applies it through the same `TabletopGame.addAction`
    /// path a physical toss uses — `GameObserver.actionIsPending` already
    /// plays the toss sound for any `Die20` update, the same as it does for
    /// `applyDiceRoll`'s. See CODE_AUDIT §8.2.
    func tossDieForAccessibility(dieId: EquipmentIdentifier, sides: Int) {
        let result = Int.random(in: 1...sides)
        if let equipment = tabletopGame.equipment(of: Die20.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        } else if let equipment = tabletopGame.equipment(of: Die.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        }
    }

#endif

    // MARK: - Map Sync & Fog of War

    /// Refreshes the standalone tabletop from the current game selection. The
    /// method deliberately rechecks the same map id because mapState updates can
    /// alter its photo, rooms, pins, or role without changing navigation.
    func refreshCurrentMap(isGameMaster: Bool) async {
        await handleMapChange(isGameMaster: isGameMaster)
    }

    func handleMapChange(isGameMaster: Bool) async {
        let roleChanged = self.isGameMaster != isGameMaster
        self.isGameMaster = isGameMaster

        guard let currentItemId = mapRoot.mapGameControllable.gameModel.currentItemId else {
            clearPinSelection()
            currentMapId = nil
            clearBoardImage()
            syncPawnsWithMapPins()
            Logger.gameTable.debug("No current map selected in game")
            return
        }

        guard let mapModel = await mapModel(for: currentItemId) else {
            clearPinSelection()
            currentMapId = nil
            clearBoardImage()
            syncPawnsWithMapPins()
            Logger.gameTable.error("Current item is not a MapModel")
            return
        }

        let mapChanged = currentItemId != currentMapId
        let photoMetadata = mapModel.photoId.flatMap(photoMetadata(for:))
        let photoChanged = mapModel.photoId != currentPhotoId
            || photoMetadata?.version != currentPhotoVersion
            || photoMetadata?.degrees != currentMapDegrees
        if mapChanged {
            clearPinSelection()
            fogSignature = nil
        }
        if roleChanged {
            fogSignature = nil
        }
        resetViewportPanIfFocusedRoomChanged(entries: mapModel.entries)
        currentMapId = currentItemId

        if mapChanged || photoChanged || currentMapImage == nil {
            await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
        } else {
            await replaceFogOfWarTask(isGameMaster: isGameMaster).value
        }
        syncPawnsWithMapPins()
    }

    private func loadMapPhoto(mapModel: MapModel, isGameMaster: Bool) async {
        currentPhotoId = mapModel.photoId
        guard let photoId = mapModel.photoId else {
            currentMapImage = nil
            currentMapDegrees = 0
            currentPhotoVersion = nil
            fogSignature = Self.renderSignature(
                of: mapModel,
                degrees: 0,
                isGameMaster: renderIsGameMaster,
                viewportPan: manualViewportOffset
            )
            setup.board.clearMap()
            Logger.gameTable.debug("Map has no photo")
            return
        }

        let metadata = photoMetadata(for: photoId)
        let (image, degrees) = await photoRoot.fetchPhotoImage(for: photoId, useGame: true) ?? (nil, 0)
        guard !Task.isCancelled else { return }
        guard let image else {
            currentMapImage = nil
            currentMapDegrees = 0
            currentPhotoVersion = metadata?.version
            fogSignature = nil
            setup.board.clearMap()
            Logger.gameTable.error("Failed to load photo for the current map")
            return
        }

        currentMapImage = image
        currentMapDegrees = degrees
        currentPhotoVersion = metadata?.version
        fogSignature = Self.renderSignature(
            of: mapModel,
            degrees: degrees,
            isGameMaster: renderIsGameMaster,
            viewportPan: manualViewportOffset
        )
        setup.board.updateMap(
            image: image,
            degrees: degrees,
            displayConfig: mapModel.displayConfig,
            mapModel: mapModel,
            isGameMaster: renderIsGameMaster,
            panOffset: manualViewportOffset
        )
        Logger.gameTable.debug("Map updated (rotation: \(degrees, privacy: .public)°, GM: \(isGameMaster, privacy: .public))")
    }

    /// Cancels any in-flight fog recomposite, starts a new one, and stores it as the current
    /// `fogOfWarTask` — the single choke point every fog-affecting entry point routes through
    /// so overlapping requests (rapid room toggling, a toolbar action mid-drag) supersede
    /// rather than race each other. Callers that need to wait for the result (room
    /// toggle/focus, "show/hide all", a map change) await the returned task directly instead
    /// of re-reading `fogOfWarTask`, which a nested call could have already replaced by the
    /// time they'd read it back. See CODE_AUDIT §5.5.
    @discardableResult
    private func replaceFogOfWarTask(isGameMaster: Bool) -> Task<Void, Never> {
        fogOfWarTask?.cancel()
        let task = Task { await updateFogOfWar(isGameMaster: isGameMaster) }
        fogOfWarTask = task
        return task
    }

    /// Rebuilds fog only when a value that affects the rendered board changed. Checks
    /// cancellation after every suspension point so a recomposite superseded by a newer one
    /// (via `replaceFogOfWarTask`) can't still apply its now-stale result on top. See
    /// CODE_AUDIT §5.5.
    func updateFogOfWar(isGameMaster: Bool) async {
        self.isGameMaster = isGameMaster
        guard let currentItemId = currentMapId else {
            Logger.gameTable.debug("No current map to update fog of war")
            return
        }
        guard let mapModel = await mapModel(for: currentItemId) else {
            clearBoardImage()
            Logger.gameTable.error("Current item is not a MapModel")
            return
        }
        guard !Task.isCancelled else { return }
        resetViewportPanIfFocusedRoomChanged(entries: mapModel.entries)
        let metadata = mapModel.photoId.flatMap(photoMetadata(for:))
        if metadata?.version != currentPhotoVersion
            || metadata?.degrees != currentMapDegrees {
            await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
            return
        }
        guard let mapImage = currentMapImage,
              currentPhotoId == mapModel.photoId else {
            await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
            return
        }

        let signature = Self.renderSignature(
            of: mapModel,
            degrees: currentMapDegrees,
            isGameMaster: renderIsGameMaster,
            viewportPan: manualViewportOffset
        )
        guard signature != fogSignature else { return }
        guard !Task.isCancelled else { return }
        fogSignature = signature

        setup.board.updateMap(
            image: mapImage,
            degrees: currentMapDegrees,
            displayConfig: mapModel.displayConfig,
            mapModel: mapModel,
            isGameMaster: renderIsGameMaster,
            panOffset: manualViewportOffset
        )
        Logger.gameTable.debug("Fog of war updated - \(mapModel.entries.filter { !$0.isShown }.count, privacy: .public) hidden areas (GM: \(isGameMaster, privacy: .public))")
    }

    /// The effective GM/fog flag used for rendering only — real role-gating
    /// (`isGameMaster`, checked everywhere a mutation is permission-gated)
    /// stays untouched by the local preview. Reader and player both preview
    /// as fog-limited today; the 3D board has no separate "full view without
    /// GM overlays" render path the way the 2D map's reader mode does.
    private var renderIsGameMaster: Bool {
        isGameMaster && displayMode != .player
    }

    /// Includes all board inputs, not merely room visibility, so edits to room
    /// geometry, map dimensions, display configuration, photo, and role render.
    private static func renderSignature(
        of mapModel: MapModel,
        degrees: Double,
        isGameMaster: Bool,
        viewportPan: CGPoint
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(mapModel.id)
        hasher.combine(mapModel.photoId)
        hasher.combine(mapModel.width)
        hasher.combine(mapModel.height)
        hasher.combine(degrees)
        hasher.combine(isGameMaster)
        hasher.combine(mapModel.displayConfig)
        hasher.combine(viewportPan.x)
        hasher.combine(viewportPan.y)
        for entry in mapModel.entries {
            hasher.combine(entry.id)
            hasher.combine(entry.coordinates)
            hasher.combine(entry.isHexGrid)
            hasher.combine(entry.isShown)
            hasher.combine(entry.focused)
        }
        return hasher.finalize()
    }

    // MARK: - Viewport & Board Projection

    /// The crop rect (in the given map's oriented coordinate space, same
    /// units as `MapEntryModel.coordinates`) the 3D board should show: the
    /// full map by default, or — when a room is focused — a room-centered,
    /// aspect-matched crop that fills the board with that room. Mirrors the
    /// 2D map's own room-focus zoom (`MapEditorSession.focus(on:)`), but as a
    /// fill-and-clip crop rather than a scroll, since the 3D board is a
    /// fixed-size surface, not a scrollable canvas. Shared here because both
    /// `GameSetup` implementations (visionOS and iOS/macOS) duplicate
    /// `MapTableProjection` and its board texture rendering — this keeps the
    /// geometry itself in one place.
    /// `panOffset` shifts the crop's center before clamping — the local,
    /// per-client adjustment from dragging the map surface while zoomed (see
    /// `manualViewportOffset`). Zero by default: the auto-fit crop centered
    /// on the focused room, unchanged from before panning existed.
    static func boardFocusRect(entries: [MapEntryModel], imageSize: CGSize, panOffset: CGPoint = .zero) -> CGRect {
        let fullRect = CGRect(origin: .zero, size: imageSize)
        guard imageSize.width > 0, imageSize.height > 0,
              let focused = entries.first(where: \.focused),
              let bounds = boundingBox(of: focused.coordinates),
              bounds.width > 0, bounds.height > 0 else {
            return fullRect
        }

        // Same fit computation the 2D map's `focus(on:)` uses (padding + the
        // smaller of the two axis scales), just used to size a crop rect
        // instead of a viewport scale — `scale` is floored at 1 so a room
        // that's already as big as (or bigger than) the full map falls back
        // to showing the whole map rather than "zooming out" past it.
        let padding: CGFloat = 50
        let paddedSize = CGSize(width: bounds.width + padding * 2, height: bounds.height + padding * 2)
        let widthScale = imageSize.width / paddedSize.width
        let heightScale = imageSize.height / paddedSize.height
        let scale = max(min(widthScale, heightScale), 1)
        guard scale.isFinite, scale > 0 else { return fullRect }

        let cropSize = CGSize(width: imageSize.width / scale, height: imageSize.height / scale)
        var origin = CGPoint(
            x: bounds.midX - cropSize.width / 2 + panOffset.x,
            y: bounds.midY - cropSize.height / 2 + panOffset.y
        )
        origin.x = min(max(origin.x, 0), imageSize.width - cropSize.width)
        origin.y = min(max(origin.y, 0), imageSize.height - cropSize.height)
        return CGRect(origin: origin, size: cropSize)
    }

    private static func boundingBox(of coordinates: [CGPoint]) -> CGRect? {
        guard let first = coordinates.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in coordinates.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var rooms: [MapEntryModel] {
        currentMapModel()?.entries ?? []
    }

    /// The room the game master currently has zoomed/focused, mirroring the
    /// 2D map's own notion of a focus room. Used by the shared
    /// `ChooseMapPinsButton` toolbar control to know where a newly added
    /// monster pin should land.
    var focusedRoomId: UUID? {
        rooms.first(where: \.focused)?.id
    }

    private func resetViewportPanIfFocusedRoomChanged(entries: [MapEntryModel]) {
        let currentFocusedRoomId = entries.first(where: \.focused)?.id
        guard currentFocusedRoomId != lastFocusedRoomId else { return }
        lastFocusedRoomId = currentFocusedRoomId
        manualViewportOffset = .zero
    }

    /// Pans the zoomed viewport by a map-coordinate delta — dragging the map
    /// surface while a room is focused. Purely a local render adjustment
    /// (`manualViewportOffset`, folded into `boardFocusRect`); never touches
    /// map data, so it works the same for the game master and every player,
    /// each framing their own view independently.
    private func panViewport(by delta: CGPoint) {
        guard focusedRoomId != nil else { return }
        // Dragging right should bring content on the left into view (like
        // dragging a photo, not scrolling a window onto it) — the visible
        // crop moves opposite the finger.
        manualViewportOffset.x -= delta.x
        manualViewportOffset.y -= delta.y
        replaceFogOfWarTask(isGameMaster: isGameMaster)
        syncPawnsWithMapPins()
    }

    /// Entry point for `GameTableView.viewportPanGesture`: converts a drag's
    /// start/end table positions into a map-coordinate delta using whatever
    /// projection is currently on screen (so the pan tracks the finger
    /// exactly, at any zoom level), then pans by it. No-ops without a
    /// focused room — there's no crop to pan within otherwise.
    func panViewport(fromTableStart start: SIMD3<Float>, toTableEnd end: SIMD3<Float>, expectedRoomId: UUID?) {
        // Discards the commit if the focused room changed mid-gesture — e.g. a network-driven
        // focus change from the GM's own device while this player was mid-drag. Applying the
        // delta against a since-changed crop/baseline would otherwise produce a visible,
        // nonsensical jump instead of just dropping the now-meaningless drag. See CODE_AUDIT §5.12.
        guard let expectedRoomId, focusedRoomId == expectedRoomId,
              let mapModel = currentMapModel() else { return }
        // Falls back to the rendered image's own size when the map has no explicit
        // width/height, matching `pinDragEnded`'s fallback — without it, panning was a silent
        // no-op on such maps (pin-dropping still worked) while every other coordinate path
        // already handled this case. See CODE_AUDIT §5.11.
        let coordinateSize: CGSize
        if mapModel.width > 0, mapModel.height > 0 {
            coordinateSize = CGSize(width: mapModel.width, height: mapModel.height)
        } else if let mapImage = currentMapImage {
            coordinateSize = MapTableProjection.orientedImageSize(
                mapImage.fixedSize,
                degrees: currentMapDegrees
            )
        } else {
            return
        }
        let projection = MapTableProjection(
            imageSize: coordinateSize,
            degrees: 0,
            focusRect: Self.boardFocusRect(
                entries: mapModel.entries,
                imageSize: coordinateSize,
                panOffset: manualViewportOffset
            )
        )
        let startLocation = projection.mapLocation(for: start)
        let endLocation = projection.mapLocation(for: end)
        panViewport(by: CGPoint(x: endLocation.x - startLocation.x, y: endLocation.y - startLocation.y))
    }

    /// Re-syncs pawns and re-broadcasts after a map mutation made outside this
    /// model — e.g. `ChooseMapPinsButton` adding monster pins directly through
    /// `EditController`, bypassing this model's own mutation methods (which
    /// all sync/broadcast themselves). Local sync always runs so the game
    /// master sees the change immediately; broadcasting respects `isStreaming`
    /// the same way the 2D toolbar's "Share Map" toggle does.
    func syncAfterExternalEdit() {
        syncPawnsWithMapPins()
        guard isStreaming, isGameMaster, let mapId = currentMapId else { return }
        broadcastMapState(for: mapId)
    }

    var pointer: MapPinModel? {
        currentMapModel()?.pointer
    }

    // MARK: - GameToolBarSession

    /// Reflects the pointer pawn's real visibility rather than tracking a
    /// separate armed/disarmed flag — the 3D table has no mouse-follow
    /// concept the way the 2D map does, so "pointing" and "pointer visible"
    /// are the same thing here. `GameToolBar.togglePointingMode()` mutates
    /// the pointer directly through `MapRootModel`; this just reports the
    /// result, so the setter is a no-op.
    var isPointing: Bool {
        get { pointer?.isShown ?? false }
        set {}
    }

    var pinScale: CGFloat {
        get { currentMapModel()?.pinScale ?? 1 }
        set { currentMapModel()?.pinScale = newValue }
    }

    var hexScale: Double {
        get { currentMapModel()?.hexMapScale ?? 0 }
        set { currentMapModel()?.hexMapScale = newValue }
    }

    var isHexMap: Bool {
        rooms.contains(where: \.isHexGrid)
    }

    var canReshare: Bool {
        lastPinScale != pinScale
            || lastHexScale != hexScale
            || lastIsHexMap != isHexMap
    }

    func resetReshare() {
        lastPinScale = pinScale
        lastHexScale = hexScale
        lastIsHexMap = isHexMap
    }

    /// Toggles the hex overlay grid via the same `EditController` grid
    /// generation the 2D map editor uses (exposed publicly for this by
    /// `MapRootModel.toggleHexMap(itemId:)`), then re-syncs the board so the
    /// grid appears immediately.
    func toggleHexMap() {
        guard let mapId = currentMapId else { return }
        _ = mapRoot.toggleHexMap(itemId: mapId)
        syncAfterExternalEdit()
    }

    func sendMapUpdates() {
        guard let mapId = currentMapId else { return }
        broadcastMapState(for: mapId)
    }

    /// Game-master room action used by every tabletop platform.
    func toggleRoomVisibility(_ roomId: UUID) async {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.toggleRoom(itemId: mapId, roomId: roomId) else { return }
        await replaceFogOfWarTask(isGameMaster: true).value
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    /// Toggles the same "focused" flag the 2D map's room long-press uses to
    /// zoom its viewport to a room — keeping a concurrently open 2D map view
    /// in sync, and, unlike the 2D map's scrollable viewport, re-rendering
    /// the 3D board's own fixed-size texture as a fill-and-clip crop onto the
    /// focused room (see `boardFocusRect`).
    func toggleRoomFocus(_ roomId: UUID) async {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.toggleRoomFocus(itemId: mapId, roomId: roomId) else { return }
        await replaceFogOfWarTask(isGameMaster: true).value
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    /// Shows or hides the full map with one render/sync/network transaction.
    func setAllRoomsShown(_ isShown: Bool) async {
        guard isGameMaster, let mapId = currentMapId else { return }
        let roomIds = rooms.map(\.id)
        guard mapRoot.mapGameControllable.setRoomsShown(
            itemId: mapId,
            roomIds: roomIds,
            isShown: isShown
        ) else { return }
        await replaceFogOfWarTask(isGameMaster: true).value
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    func togglePointerVisibility() {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.togglePointer(itemId: mapId) else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    /// Places and reveals the pointer at the map center without requiring the
    /// 2D map window. Both mutations are delivered in one mapState message.
    func movePointerToMapCenter() {
        guard isGameMaster, let mapId = currentMapId, let mapModel = currentMapModel() else { return }
        let center = CGPoint(x: mapModel.width / 2, y: mapModel.height / 2)
        let moved = mapRoot.mapGameControllable.movePointer(itemId: mapId, location: center)
        let revealed = mapModel.pointer.isShown
            ? false
            : mapRoot.mapGameControllable.togglePointer(itemId: mapId)
        guard moved || revealed else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    /// Adds a set selected by a future platform-specific character picker.
    /// Keeping the mutation here avoids coupling the tabletop to MapEditor.
    func addMonstersAtMapCenter(_ monsters: [ItemRowModel]) {
        guard isGameMaster, let mapId = currentMapId,
              mapRoot.mapGameControllable.addMonstersAtMapCenter(
                itemId: mapId,
                monsters: monsters
              ) else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    // MARK: - Pin Thumbnails & Menu

    /// Loads the pin's photo thumbnail (2D pin pipeline) onto the 3D token.
    func loadPinThumbnail(pinId: UUID, photoId: UUID) async {
        defer {
            if pendingPinPhotoIds[pinId] == photoId {
                pendingPinPhotoIds[pinId] = nil
            }
            pendingThumbnailTasks[pinId] = nil
        }
        guard !Task.isCancelled, let cache = photoRoot.cacheControllable else { return }
        var image = await cache.thumbnail(for: photoId)
        if image == nil {
            guard let item = await photoRoot.itemControllable.item(for: photoId) else { return }
            await cache.thumbnailId(for: photoId, item: item)
            image = await cache.thumbnail(for: photoId)
        }
        guard !Task.isCancelled else { return }
        let currentPin = currentMapModel().flatMap { mapModel in
            pinId == mapModel.pointer.id
                ? mapModel.pointer
                : mapModel.mapPins.first(where: { $0.id == pinId })
        }
        guard currentPin?.photoId == photoId,
              let image,
              let pawn = setup.pinPawns.first(where: { $0.pinId == pinId }) else { return }
        pawn.setPhotoTexture(image)
        pawn.loadedPhotoId = photoId
    }

    func beginPinPhotoLoad(pinId: UUID, photoId: UUID) -> Bool {
        guard pendingPinPhotoIds[pinId] != photoId else { return false }
        pendingPinPhotoIds[pinId] = photoId
        return true
    }

    /// Records the thumbnail-load `Task` spawned for `pinId`, cancelling any
    /// still-running load for that same pin it supersedes.
    func trackThumbnailTask(for pinId: UUID, _ task: Task<Void?, Never>) {
        pendingThumbnailTasks[pinId]?.cancel()
        pendingThumbnailTasks[pinId] = task
    }

    /// The master moves every pin. A player moves its own pin and may move the
    /// shared pointer while the game master has made that pointer visible,
    /// matching the existing 2D game-map contract.
    func canMovePin(_ pinId: UUID) -> Bool {
        guard let mapModel = currentMapModel() else { return false }
        if pinId == mapModel.pointer.id {
            return isGameMaster || mapModel.pointer.isShown
        }
        return isGameMaster || pinId == playerPinId
    }

    /// Registers the SwiftUI attachment used for the game-master pin menu.
    /// It remains parented to the table root rather than the pawn so pin size
    /// and zoom transforms never scale the controls.
    func registerPinMenuAttachment(_ attachment: Entity) {
        pinMenuAttachment = attachment
        attachment.components.set(BillboardComponent())
        if attachment.parent == nil {
            renderer.root.addChild(attachment)
        }
        updatePinMenuAttachmentPosition()
    }

    // MARK: - Pin Selection & Gestures

    func updateSelectedPinState(mapModel: MapModel?) {
        guard isGameMaster,
              let selectedPinId,
              let pin = mapModel?.mapPins.first(where: { $0.id == selectedPinId }),
              setup.pinPawns.contains(where: { $0.pinId == selectedPinId }) else {
            clearPinSelection()
            return
        }
        selectedPin = pin
        updatePinMenuAttachmentPosition()
    }

    func clearPinSelection() {
        selectedPinId = nil
        selectedPin = nil
        pinMenuAttachment?.isEnabled = false
    }

    func updatePinMenuAttachmentPosition(cachedPawn: PinPawn? = nil) {
        guard isGameMaster,
              selectedPin != nil,
              let selectedPinId,
              let attachment = pinMenuAttachment,
              let pawn = cachedPawn ?? setup.pinPawns.first(where: { $0.pinId == selectedPinId }) else {
            pinMenuAttachment?.isEnabled = false
            return
        }
        let pinPosition = pawn.entity.position
        attachment.position = SIMD3<Float>(pinPosition.x, pinPosition.y + 0.09, pinPosition.z)
        attachment.isEnabled = true
    }

    /// Pin drag: follow the finger on the board plane. Runs on every `.onChanged` delta —
    /// potentially dozens of times per second during one drag — so the resolved pawn is
    /// cached across calls instead of re-scanning `pinPawns` (and, when the dragged pin is
    /// also the selected one, a second scan inside `updatePinMenuAttachmentPosition`) on every
    /// tick. See CODE_AUDIT §7.3.
    func pinDragChanged(pinId: UUID, position: SIMD3<Float>) {
        guard canMovePin(pinId) else { return }
        let pawn: PinPawn
        if let cachedDragPawn, cachedDragPawn.pinId == pinId {
            pawn = cachedDragPawn.pawn
        } else {
            guard let found = setup.pinPawns.first(where: { $0.pinId == pinId }) else { return }
            pawn = found
            cachedDragPawn = (pinId, found)
        }
        pawn.entity.position = SIMD3<Float>(position.x, MapTableProjection.pinHeight, position.z)
        if selectedPinId == pinId {
            updatePinMenuAttachmentPosition(cachedPawn: pawn)
        }
    }

    /// Pin drop: write the move back into the map model, then network it.
    func pinDragEnded(pinId: UUID, position: SIMD3<Float>) {
        cachedDragPawn = nil
        guard canMovePin(pinId), let mapId = currentMapId,
              let mapImage = currentMapImage,
              let mapModel = currentMapModel() else { return }
        let coordinateSize = mapModel.width > 0 && mapModel.height > 0
            ? CGSize(width: mapModel.width, height: mapModel.height)
            : MapTableProjection.orientedImageSize(
                mapImage.fixedSize,
                degrees: currentMapDegrees
            )
        // Must match whatever projection actually rendered the board (and
        // thus whatever the user saw under their finger) — otherwise a pin
        // dropped while a room is focused/zoomed converts back to the wrong
        // map location, since the un-cropped projection denormalizes against
        // the whole map instead of the visible crop.
        let projection = MapTableProjection(
            imageSize: coordinateSize,
            degrees: 0,
            focusRect: Self.boardFocusRect(
                entries: mapModel.entries,
                imageSize: coordinateSize,
                panOffset: manualViewportOffset
            )
        )
        let location = projection.mapLocation(
            for: SIMD3<Float>(position.x, MapTableProjection.pinHeight, position.z)
        )

        if pinId == mapModel.pointer.id {
            guard mapRoot.mapGameControllable.movePointer(itemId: mapId, location: location) else { return }
            syncPawnsWithMapPins()
            if isGameMaster {
                broadcastMapState(for: mapId)
            } else {
                sendPlayerPointerUpdate(mapId: mapId)
            }
            return
        }

        guard mapRoot.mapGameControllable.movePin(
            itemId: mapId,
            pinId: pinId,
            location: location
        ) else { return }
        syncPawnsWithMapPins()
        if isGameMaster {
            broadcastMapState(for: mapId)
        } else {
            sendPlayerPinUpdate(mapId: mapId, pinId: pinId)
        }
    }

    /// A tap toggles the shared highlight for both roles. On the master this
    /// first adds a missing combatant while Surprise is being prepared. Once
    /// the row exists, taps feed the active battle row's defender set.
    func pinTapped(pinId: UUID) {
        guard let mapId = currentMapId,
              let mapModel = currentMapModel(),
              pinId != mapModel.pointer.id,
              setup.pinPawns.contains(where: { $0.pinId == pinId }) else { return }
        if addPinToBattleRound(pinId: pinId) {
            return
        }
        guard mapRoot.mapGameControllable.toggleHighlightPin(itemId: mapId, pinId: pinId) else { return }
        syncPawnsWithMapPins()
        if isGameMaster {
            broadcastMapState(for: mapId)
        } else {
            sendPlayerPinUpdate(mapId: mapId, pinId: pinId)
        }
    }

    /// The game-master action menu is local presentation state and therefore
    /// belongs to a long press rather than competing with battle highlighting.
    func pinLongPressed(pinId: UUID) {
        guard isGameMaster,
              let mapModel = currentMapModel(),
              pinId != mapModel.pointer.id,
              setup.pinPawns.contains(where: { $0.pinId == pinId }) else { return }
        if selectedPinId == pinId {
            clearPinSelection()
        } else {
            selectedPinId = pinId
            updateSelectedPinState(mapModel: mapModel)
        }
    }

    /// Double tap toggles shared zoom for both roles.
    func pinDoubleTapped(pinId: UUID) {
        guard let mapId = currentMapId,
              pinId != currentMapModel()?.pointer.id,
              setup.pinPawns.contains(where: { $0.pinId == pinId }),
              mapRoot.mapGameControllable.zoomPin(itemId: mapId, pinId: pinId) else { return }
        syncPawnsWithMapPins()
        if isGameMaster {
            broadcastMapState(for: mapId)
        } else {
            sendPlayerPinUpdate(mapId: mapId, pinId: pinId)
        }
    }

    func toggleSelectedPinDead() {
        guard isGameMaster, let mapId = currentMapId, let selectedPinId,
              mapRoot.mapGameControllable.toggleDeadPin(itemId: mapId, pinId: selectedPinId) else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    var canAddSelectedPinToBattleRound: Bool {
        guard isGameMaster,
              let selectedPinId else {
            return false
        }
        let battleRound = mapRoot.mapGameControllable.battleRoundModel
        return battleRound.isPreparingSurprise
            && battleRound.combatant(pinId: selectedPinId) == nil
    }

    func addSelectedPinToBattleRound() {
        guard let selectedPinId else { return }
        _ = addPinToBattleRound(pinId: selectedPinId)
    }

    func toggleSelectedPinVisibility() {
        guard isGameMaster, let mapId = currentMapId, let selectedPinId,
              mapRoot.mapGameControllable.togglePin(itemId: mapId, pinId: selectedPinId) else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    func resizeSelectedPin() {
        guard isGameMaster, let mapId = currentMapId, let selectedPinId,
              mapRoot.mapGameControllable.resizePin(itemId: mapId, pinId: selectedPinId) else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    func toggleSelectedPinZoom() {
        guard isGameMaster, let mapId = currentMapId, let selectedPinId,
              mapRoot.mapGameControllable.zoomPin(itemId: mapId, pinId: selectedPinId) else { return }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
    }

    @discardableResult
    private func addPinToBattleRound(pinId: UUID) -> Bool {
        guard isGameMaster,
              let mapId = currentMapId,
              mapRoot.mapGameControllable.addBattleCombatant(
                  itemId: mapId,
                  pinId: pinId
              ) else {
            return false
        }
        syncPawnsWithMapPins()
        broadcastMapState(for: mapId)
        broadcastBattleRoundState(for: mapId)
        return true
    }

    // MARK: - Broadcast Helpers

    private func mapModel(for mapId: UUID) async -> MapModel? {
        if let liveMap = mapRoot.mapGameControllable.gameModel.itemData[mapId] as? MapModel {
            return liveMap
        }
        return await mapRoot.itemControllable.item(for: mapId) as? MapModel
    }

    func currentMapModel() -> MapModel? {
        guard let currentMapId else { return nil }
        return (mapRoot.mapGameControllable.gameModel.itemData[currentMapId] as? MapModel)
            ?? (mapRoot.itemControllable.itemSync(for: currentMapId) as? MapModel)
    }

    private func photoMetadata(for photoId: UUID) -> (version: Int, degrees: Double)? {
        let photo = (photoRoot.gameControllable.gameModel.itemData[photoId] as? PhotoModel)
            ?? (photoRoot.itemControllable.itemSync(for: photoId) as? PhotoModel)
        guard let photo else { return nil }
        return (photo.version, photo.degrees)
    }

    private func clearBoardImage() {
        currentPhotoId = nil
        currentPhotoVersion = nil
        currentMapImage = nil
        currentMapDegrees = 0
        fogSignature = nil
        setup.board.clearMap()
    }

    private func broadcastMapState(for mapId: UUID) {
        networkActions?.game(
            mapRoot.mapGameControllable.networkMapUpdate(for: mapId),
            .mapState,
            nil
        )
    }

    private func broadcastBattleRoundState(for mapId: UUID) {
        guard let battleUpdate = mapRoot.mapGameControllable.networkBattleRoundUpdate(
            for: mapId
        ) else {
            return
        }
        networkActions?.game(battleUpdate, .battleRound, nil)
    }

    private func sendPlayerPinUpdate(mapId: UUID, pinId: UUID) {
        guard let pinData = mapRoot.mapGameControllable.networkPin(
            itemId: mapId,
            pinId: pinId
        ) else { return }
        networkActions?.game(pinData, .mapPin, nil)
    }

    private func sendPlayerPointerUpdate(mapId: UUID) {
        guard let pointerData = mapRoot.mapGameControllable.networkPointer(itemId: mapId) else { return }
        networkActions?.game(pointerData, .mapPin, nil)
    }

    isolated deinit {
        pendingThumbnailTasks.values.forEach { $0.cancel() }
        fogOfWarTask?.cancel()
#if os(visionOS)
        tabletopGame.removeObserver(observer)
        tabletopGame.removeRenderDelegate(renderer)
#endif
    }
}

/// Lets the 3D table host the exact same `GameToolBar` (and its button
/// actions) as the 2D map — see `GameToolBarSession` for what this promises.
extension GameTableModel: GameToolBarSession {}

extension Logger {
    static let gameTable = Logger(subsystem: subsystem, category: "GameTable")
}

#endif
