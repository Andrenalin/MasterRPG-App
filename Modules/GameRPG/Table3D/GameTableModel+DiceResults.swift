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
    /// shows is the dice overlay's result for that group; see `GameDiceResultPopover`.
    func updateDiceResults(snapshot: TableSnapshot, visualState: TableVisualState) {
        let now = ContinuousClock.now

        for seat in setup.seats where seat.id != PlayerSeat.guestSeat {
            updateDiceResult(
                for: .seat(seat.id),
                dice: seatDice(seat.id, snapshot: snapshot),
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
                now: now,
                snapshot: snapshot,
                visualState: visualState
            )
        }
    }

    private func updateDiceResult(
        for group: TableDiceGroup,
        dice: [TableDie],
        now: ContinuousClock.Instant,
        snapshot: TableSnapshot,
        visualState: TableVisualState
    ) {
        let faces = dice.filter { TableDieValue.isRolled($0.value) }.map(\.value)
        let isResting = !faces.isEmpty && dice.allSatisfy {
            isAtRest($0.id, snapshot: snapshot, visualState: visualState)
        }
        guard isResting else {
            diceRestingSince[group] = nil
            hideDiceResult(for: group)
            return
        }

        // New faces start the wait again: the dice may not have begun to turn yet.
        if diceRestingSince[group]?.faces != faces {
            diceRestingSince[group] = (faces, now)
            hideDiceResult(for: group)
        }
        guard let start = diceRestingSince[group]?.start,
              now - start >= TableDiceRest.settleDuration,
              !shownDiceGroups.contains(group) else { return }

        // The dice may have come to rest somewhere else.
        diceResultPopovers[group]?.show(at: diceResultTip(above: dice))
        shownDiceGroups.insert(group)
    }

    func hideDiceResult(for group: TableDiceGroup) {
        guard shownDiceGroups.contains(group) else { return }
        shownDiceGroups.remove(group)
        diceResultPopovers[group]?.hide()
    }

    /// The dice of a seat's pool that are on the table, with their synced values.
    private func seatDice(_ seat: TableSeatIdentifier, snapshot: TableSnapshot) -> [TableDie] {
        var dice: [TableDie] = []
        for dieId in setup.playerD20Ids[seat] ?? [] {
            guard let (die, state) = snapshot.equipment(of: Die20.self, matching: dieId),
                  state.value != TableDieValue.parked else { continue }
            dice.append((dieId, state.value, die.entity))
        }
        for dieId in setup.playerD6Ids[seat] ?? [] {
            guard let (die, state) = snapshot.equipment(of: Die.self, matching: dieId),
                  state.value != TableDieValue.parked else { continue }
            dice.append((dieId, state.value, die.entity))
        }
        return dice
    }

    /// A guest's dice on the table. `nil` unless every one of them shows the value this device
    /// knows of that guest's roll: the device placing the dice may know a different roll, and a
    /// popover must not put a name on someone else's dice.
    private func guestDice(_ group: TableGuestDice.Group, snapshot: TableSnapshot) -> [TableDie]? {
        let d20Ids = setup.playerD20Ids[PlayerSeat.guestSeat] ?? []
        let d6Ids = setup.playerD6Ids[PlayerSeat.guestSeat] ?? []
        var dice: [TableDie] = []
        for die in group.dice {
            if die.isD20 {
                guard d20Ids.indices.contains(die.slot),
                      let (equipment, state) = snapshot.equipment(of: Die20.self, matching: d20Ids[die.slot]),
                      state.value == die.value else { return nil }
                dice.append((d20Ids[die.slot], state.value, equipment.entity))
            } else {
                guard d6Ids.indices.contains(die.slot),
                      let (equipment, state) = snapshot.equipment(of: Die.self, matching: d6Ids[die.slot]),
                      state.value == die.value else { return nil }
                dice.append((d6Ids[die.slot], state.value, equipment.entity))
            }
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
        guard isGuestDiceDriver,
              let d20Ids = setup.playerD20Ids[PlayerSeat.guestSeat],
              let d6Ids = setup.playerD6Ids[PlayerSeat.guestSeat] else { return }

        let positions = TableGuestDice.positions(groupSizes: guestGroups.map(\.dice.count))
        var d20Targets: [Int: (value: Int, pose: TableVisualState.Pose2D)] = [:]
        var d6Targets: [Int: (value: Int, pose: TableVisualState.Pose2D)] = [:]
        for (group, groupPositions) in zip(guestGroups, positions) {
            for (die, position) in zip(group.dice, groupPositions) {
                let target = (
                    value: die.value,
                    pose: TableVisualState.Pose2D(position: .init(x: position.x, z: position.z), rotation: .zero)
                )
                if die.isD20 {
                    d20Targets[die.slot] = target
                } else {
                    d6Targets[die.slot] = target
                }
            }
        }

        let parked = (value: TableDieValue.parked, pose: TableVisualState.Pose2D.parkedDicePose)
        for (slot, dieId) in d20Ids.enumerated() {
            guard let equipment = tabletopGame.equipment(of: Die20.self, matching: dieId) else { continue }
            updateDieSlot(equipment, target: d20Targets[slot] ?? parked)
        }
        for (slot, dieId) in d6Ids.enumerated() {
            guard let equipment = tabletopGame.equipment(of: Die.self, matching: dieId) else { continue }
            updateDieSlot(equipment, target: d6Targets[slot] ?? parked)
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
