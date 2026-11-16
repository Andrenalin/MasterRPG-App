// @copyright André Trettin

#if os(visionOS)
import Foundation
import RealityKit
import Spatial
import TabletopKit

extension GameTableModel {
    // MARK: - Dice Results

    /// A die of a group on the table, with its synced value.
    typealias TableDie = (id: EquipmentIdentifier, value: Int, entity: Entity)

    /// Keeps every dice group's result popover in step with its dice. Runs on every frame
    /// (`GameRenderer.onUpdate`); publishes only when a popover goes up or down.
    ///
    /// A group's popover is up once its dice have been rolled and lie where their state puts
    /// them. It goes away as soon as a die is picked up, tossed or turns to a new face, and
    /// comes back when all of them have settled again — in the place they then lie. What it
    /// shows is the dice overlay's result for that group; see `GameDiceResultPopover`. This
    /// device's own dice have theirs before they are rolled as well, for its roll button.
    func updateDiceResults(snapshot: TableSnapshot, visualState: TableVisualState) {
        let now = ContinuousClock.now
        let localSeat = snapshot.seat(of: PlayerSeat.self, for: tabletopGame.localPlayer)?.0.id

        for seat in setup.seats where seat.id != PlayerSeat.guestSeat {
            updateDiceResult(
                for: .seat(seat.id),
                dice: seatDice(seat.id, snapshot: snapshot),
                isLocalSeat: seat.id == localSeat,
                now: now,
                snapshot: snapshot,
                visualState: visualState
            )
        }
        for index in guestGroups.indices {
            // `nil` while the table does not show this guest's roll (yet).
            updateDiceResult(
                for: .guest(index),
                dice: guestDice(guestGroups[index], snapshot: snapshot) ?? [],
                isLocalSeat: false,
                now: now,
                snapshot: snapshot,
                visualState: visualState
            )
        }
    }

    private func updateDiceResult(
        for group: TableDiceGroup,
        dice: [TableDie],
        isLocalSeat: Bool,
        now: ContinuousClock.Instant,
        snapshot: TableSnapshot,
        visualState: TableVisualState
    ) {
        let values = dice.map(\.value)
        let isResting = TableDieValue.hasPopover(values, isLocalSeat: isLocalSeat) && dice.allSatisfy {
            isAtRest($0.id, snapshot: snapshot, visualState: visualState)
        }
        guard isResting else {
            diceRestingSince[group] = nil
            hideDiceResult(for: group)
            return
        }

        // New values start the wait again: the dice may not have begun to turn yet.
        if diceRestingSince[group]?.values != values {
            diceRestingSince[group] = (values, now)
            hideDiceResult(for: group)
        }
        guard let start = diceRestingSince[group]?.start,
              now - start >= TableDiceRest.settleDuration,
              !shownDiceGroups.contains(group) else { return }

        // The dice may have come to rest somewhere else.
        shownDiceGroups.insert(group)
        applyDiceResultVisibility(for: group, tip: diceResultTip(above: dice))
    }

    func hideDiceResult(for group: TableDiceGroup) {
        guard shownDiceGroups.contains(group) else { return }
        shownDiceGroups.remove(group)
        applyDiceResultVisibility(for: group, tip: nil)
    }

    /// Brings a group's attachment in step with `shownDiceGroups`, after the frame callback
    /// this is called from has returned.
    ///
    /// TabletopKit calls `onUpdate` inside a Core Animation commit. Enabling the attachment there
    /// activates its hosting entity at once, and SwiftUI then hands the keyboard back to a text
    /// field the popover still has in focus — the quick editor of the own dice's compare value,
    /// when the new value changed the number of dice and the popover came back for them. UIKit
    /// cannot synchronize the keyboard's scene during a commit and aborts with "Failed to
    /// register pre-fence handler: transactionPhase=3". Disabling it resigns that focus the same
    /// way, so both wait for the next turn of the main actor.
    private func applyDiceResultVisibility(for group: TableDiceGroup, tip: SIMD3<Float>?) {
        Task { @MainActor [weak self] in
            guard let self, let popover = diceResultPopovers[group] else { return }
            // The group may have changed its mind since: only the latest state counts.
            if let tip, shownDiceGroups.contains(group) {
                popover.show(at: tip)
            } else if !shownDiceGroups.contains(group) {
                popover.hide()
            }
        }
    }

    /// The dice of a seat's pool that are on the table, with their synced values.
    private func seatDice(_ seat: TableSeatIdentifier, snapshot: TableSnapshot) -> [TableDie] {
        var dice: [TableDie] = []
        for kind in TableDieKind.allCases {
            for dieId in setup.dieIds(kind, seat: seat) ?? [] {
                guard let (entity, value) = Self.dieEntityAndValue(kind, dieId, snapshot: snapshot),
                      value != TableDieValue.parked else { continue }
                dice.append((dieId, value, entity))
            }
        }
        return dice
    }

    /// The entity and synced value of a pool die, whatever its kind.
    private static func dieEntityAndValue(
        _ kind: TableDieKind,
        _ dieId: EquipmentIdentifier,
        snapshot: TableSnapshot
    ) -> (entity: Entity, value: Int)? {
        switch kind {
            case .d20:
                snapshot.equipment(of: Die20.self, matching: dieId).map { ($0.0.entity, $0.1.value) }
            case .d3:
                snapshot.equipment(of: Die3.self, matching: dieId).map { ($0.0.entity, $0.1.value) }
            case .d4:
                snapshot.equipment(of: Die4.self, matching: dieId).map { ($0.0.entity, $0.1.value) }
            case .d12:
                snapshot.equipment(of: Die12.self, matching: dieId).map { ($0.0.entity, $0.1.value) }
            case .d10:
                snapshot.equipment(of: Die10.self, matching: dieId).map { ($0.0.entity, $0.1.value) }
            case .d8:
                snapshot.equipment(of: Die8.self, matching: dieId).map { ($0.0.entity, $0.1.value) }
            case .d6:
                snapshot.equipment(of: Die6.self, matching: dieId).map { ($0.0.entity, $0.1.value) }
        }
    }

    /// A guest's dice on the table. `nil` unless every one of them shows the value this device
    /// knows of that guest's roll: the device placing the dice may know a different roll, and a
    /// popover must not put a name on someone else's dice.
    private func guestDice(_ group: TableGuestDice.Group, snapshot: TableSnapshot) -> [TableDie]? {
        var dice: [TableDie] = []
        for die in group.dice {
            guard let dieIds = setup.dieIds(die.kind, seat: PlayerSeat.guestSeat),
                  dieIds.indices.contains(die.slot),
                  let (entity, value) = Self.dieEntityAndValue(die.kind, dieIds[die.slot], snapshot: snapshot),
                  value == die.value else { return nil }
            dice.append((dieIds[die.slot], value, entity))
        }
        return dice
    }

    /// A die is at rest when no player holds it and it has arrived where its state puts it.
    private func isAtRest(
        _ dieId: EquipmentIdentifier,
        snapshot: TableSnapshot,
        visualState: TableVisualState
    ) -> Bool {
        guard snapshot.cursor(controlling: dieId) == nil,
              let pose = visualState.pose(matching: dieId),
              let goal = visualState.goalPose(matching: dieId) else { return false }
        return TableDiceRest.isAtRest(pose: pose, goal: goal)
    }

    /// Where the popover's arrow ends: just above the dice, over the middle of the group.
    private func diceResultTip(above dice: [TableDie]) -> SIMD3<Float> {
        let bounds = dice.reduce(BoundingBox.empty) { bounds, die in
            bounds.union(die.entity.visualBounds(relativeTo: renderer.root))
        }
        return SIMD3<Float>(bounds.center.x, bounds.max.y + Self.diceResultClearance, bounds.center.z)
    }

    /// The gap between the top of the dice and the popover's arrow.
    private static let diceResultClearance: Float = 0.015

    // MARK: Attachments

    /// Every dice group that can have a result popover: each seat a player can sit at, and as
    /// many guests as the guest seat's pool has dice.
    var diceResultGroups: [TableDiceGroup] {
        setup.seats.map(\.id).filter { $0 != PlayerSeat.guestSeat }.map { .seat($0) }
            + (0 ..< GameSetup.maxDicePerType * 2).map { .guest($0) }
    }

    /// Registers the SwiftUI attachment that shows a dice group's result. See
    /// `TablePopoverAnchor` for how it stands on the table.
    func registerDiceResultAttachment(_ attachment: Entity, for group: TableDiceGroup) {
        let popover: TablePopoverAnchor
        if let existing = diceResultPopovers[group] {
            popover = existing
        } else {
            popover = TablePopoverAnchor(name: "DiceResultAnchor")
            diceResultPopovers[group] = popover
        }
        popover.register(attachment, in: renderer.root)
        // The next frame shows it again in the right place if the group has a result.
        shownDiceGroups.remove(group)
        diceRestingSince[group] = nil
        popover.hide()
    }

    /// The attachment view reports its own height, in meters, whenever its layout changes.
    func diceResultAttachmentHeightChanged(_ height: Float, for group: TableDiceGroup) {
        diceResultPopovers[group]?.attachmentHeightChanged(height)
    }

    /// Detaches the dice result attachments before their `RealityView` tears down — see
    /// `TablePopoverAnchor.detach()`.
    func detachDiceResultAttachments() {
        diceResultPopovers.values.forEach { $0.detach() }
        shownDiceGroups = []
        diceRestingSince = [:]
    }
}

// MARK: - Guest Dice

extension GameTableModel {
    /// The latest shared rolls of the players without a table. Every device works out which of
    /// the guest seat's dice stand for whom; the device at the lowest occupied seat — the
    /// game master's, when the master is at the table — also puts the dice there, and
    /// TabletopKit shares them with everyone.
    func applyGuestRolls(_ rolls: [TableGuestRoll]) {
        let groups = TableGuestDice.groups(for: rolls, poolSize: GameSetup.maxDicePerType)
        if groups != guestGroups {
            // A group's dice, and with them its popover, may now be someone else's.
            for index in guestGroups.indices {
                diceRestingSince[.guest(index)] = nil
                hideDiceResult(for: .guest(index))
            }
            guestGroups = groups
        }
        syncGuestDice()
    }

    /// Puts the guests' dice on the table if that is this device's job. Also run when the seats
    /// change hands, because the job can then pass to this device.
    func syncGuestDice() {
        guard isGuestDiceDriver else { return }

        let positions = TableGuestDice.positions(groupSizes: guestGroups.map(\.dice.count))
        var targets: [TableDieKind: [Int: DieTarget]] = [:]
        for (group, groupPositions) in zip(guestGroups, positions) {
            for (die, position) in zip(group.dice, groupPositions) {
                targets[die.kind, default: [:]][die.slot] = (
                    value: die.value,
                    pose: TableVisualState.Pose2D(position: .init(x: position.x, z: position.z), rotation: .zero)
                )
            }
        }
        for kind in TableDieKind.allCases {
            guard let dieIds = setup.dieIds(kind, seat: PlayerSeat.guestSeat) else { continue }
            updateDiePool(kind, ids: dieIds, targets: targets[kind] ?? [:])
        }
    }

    /// Whether this device sits at the lowest occupied seat. The master's seat is the lowest
    /// of all, so the master's table places the guests' dice whenever the master is at it.
    var isGuestDiceDriver: Bool {
        var isDriver = false
        tabletopGame.withCurrentSnapshot { snapshot in
            let occupied = snapshot.seats(of: PlayerSeat.self)
                .filter { $0.1.playerID != nil && $0.0.id != PlayerSeat.guestSeat }
                .map(\.0.id.rawValue)
            guard let lowest = occupied.min(),
                  let local = snapshot.seat(of: PlayerSeat.self, for: tabletopGame.localPlayer)?.0.id
            else { return }
            isDriver = local.rawValue == lowest
        }
        return isDriver
    }
}
#endif
