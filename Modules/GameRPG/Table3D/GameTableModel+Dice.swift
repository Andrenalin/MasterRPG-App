// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import DiceRPG
import Foundation
import RealityKit
import Spatial
import TabletopKit
import os.log

extension GameTableModel {
    // MARK: - Dice

    /// Mirrors the locally focused character-sheet dice set onto the local player's own seat:
    /// shows exactly as many `Die20`/`Die3`/`Die4`/`Die12`/`Die10`/`Die8`/`Die` (d6) slots as the set needs of each type, positioned to
    /// match, and parks every other slot in this seat's pool off-table at `.parkedDicePose` with the
    /// `0` sentinel. Reuses DiceRPG's focus-dice mechanism as the trigger rather than a separate
    /// notion of "selected dice" for the table. `TabletopGame.addAction` syncs every change to every
    /// other participant, so every device shows the same shape for this seat.
    ///
    /// Only d20, d12, d10, d8, d6, d4 and d3 are backed by a table mesh, and each seat only has
    /// `GameSetup.maxDicePerType` slots per type. Extras (a homebrew "roll 8d6", or a GM
    /// batch-rolling for several NPCs) are dropped rather than mirrored, and reported through
    /// `diceOverflowCount`.
    ///
    /// Only slots whose synced value or pose actually changes are submitted: each `addAction` is a
    /// SharePlay message and plays the toss sound, so re-parking already-parked dice was pure noise.
    ///
    /// A die the sheet has not rolled yet is mirrored as `TableDieValue.unrolled`, so no other
    /// seat shows a result for it. A die tossed by hand got its value from the sheet already (see
    /// `rollTossedDie(_:)`) and stays where it landed until the sheet gives it another one.
    ///
    /// The mirrored dice are public to every seat: "Share master dice" / "Share player dice" gate
    /// the result popover, not the table (decided in CODE_AUDIT_26 §6.4).
    func applyDiceRoll(_ diceModel: DiceModel) {
        mirroredSheet = nil
        guard let seat = localSeat,
              let seatPose = setup.seats.first(where: { $0.id == seat })?.initialState.pose
        else { return }
        var sheetDieIds: [EquipmentIdentifier: UUID] = [:]

        // The dice lie in the order of the set, which is the order its result reads in — not
        // every d20 first and the d6s after them.
        let slots = TableSeatDice.slots(sides: diceModel.dice.map(\.die.max), poolSize: GameSetup.maxDicePerType)
        let layout = PlayerSeat.diceLayout(inFrontOf: seatPose, count: slots.count)
        var targets: [TableDieKind: [Int: DieTarget]] = [:]
        for (slot, pose) in zip(slots, layout) {
            let die = diceModel.dice[slot.index]
            guard let dieIds = setup.dieIds(slot.kind, seat: seat), dieIds.indices.contains(slot.slot) else { continue }
            targets[slot.kind, default: [:]][slot.slot] = (value: die.result.last ?? TableDieValue.unrolled, pose: pose)
            sheetDieIds[dieIds[slot.slot]] = die.id
        }

        for kind in TableDieKind.allCases {
            guard let dieIds = setup.dieIds(kind, seat: seat) else { continue }
            updateDiePool(kind, ids: dieIds, targets: targets[kind] ?? [:])
        }
        mirroredSheet = (diceModel.id, sheetDieIds)

        let overflowCount = diceModel.dice.count - slots.count
        diceOverflowCount = overflowCount > 0 ? overflowCount : nil
        if overflowCount > 0 {
            Logger.gameTable.warning(
                "Focused dice set had \(overflowCount, privacy: .public) dice this table couldn't represent (unsupported sides, or more than \(GameSetup.maxDicePerType, privacy: .public) of one type at this seat); those results were not mirrored onto the table"
            )
        }
    }

    /// Where a pool die goes: the value it shows and its pose.
    typealias DieTarget = (value: Int, pose: TableVisualState.Pose2D)

    /// Brings every die of one pool to its target; a slot with none is parked off the table.
    func updateDiePool(_ kind: TableDieKind, ids: [EquipmentIdentifier], targets: [Int: DieTarget]) {
        let parked: DieTarget = (value: TableDieValue.parked, pose: .parkedDicePose)
        for (slot, dieId) in ids.enumerated() {
            let target = targets[slot] ?? parked
            switch kind {
                case .d20:
                    guard let equipment = tabletopGame.equipment(of: Die20.self, matching: dieId) else { continue }
                    updateDieSlot(equipment, target: target)
                case .d3:
                    guard let equipment = tabletopGame.equipment(of: Die3.self, matching: dieId) else { continue }
                    updateDieSlot(equipment, target: target)
                case .d4:
                    guard let equipment = tabletopGame.equipment(of: Die4.self, matching: dieId) else { continue }
                    updateDieSlot(equipment, target: target)
                case .d12:
                    guard let equipment = tabletopGame.equipment(of: Die12.self, matching: dieId) else { continue }
                    updateDieSlot(equipment, target: target)
                case .d10:
                    guard let equipment = tabletopGame.equipment(of: Die10.self, matching: dieId) else { continue }
                    updateDieSlot(equipment, target: target)
                case .d8:
                    guard let equipment = tabletopGame.equipment(of: Die8.self, matching: dieId) else { continue }
                    updateDieSlot(equipment, target: target)
                case .d6:
                    guard let equipment = tabletopGame.equipment(of: Die.self, matching: dieId) else { continue }
                    updateDieSlot(equipment, target: target)
            }
        }
    }

    /// Submits a slot update only if it differs from the synced state.
    func updateDieSlot<Equip: Equipment>(
        _ equipment: Equip,
        target: (value: Int, pose: TableVisualState.Pose2D)
    ) where Equip.State == DieState {
        if handTossedDice[equipment.id] == target.value {
            // The toss put this value on the table and decides where the die lies.
            return
        }
        handTossedDice[equipment.id] = nil
        var current: DieState?
        tabletopGame.withCurrentSnapshot { snapshot in
            current = snapshot.equipment(of: Equip.self, matching: equipment.id)?.1
        }
        if let current,
           current.value == target.value,
           Self.isSamePose(current.pose, target.pose) {
            return
        }
        tabletopGame.addAction(
            .updateEquipment(equipment, value: target.value, seatControl: nil, pose: target.pose, boundingBox: nil, context: 0)
        )
    }

    private static func isSamePose(_ lhs: TableVisualState.Pose2D, _ rhs: TableVisualState.Pose2D) -> Bool {
        let tolerance = 0.000_1
        return abs(lhs.position.x - rhs.position.x) < tolerance
            && abs(lhs.position.z - rhs.position.z) < tolerance
            && abs(lhs.rotation.radians - rhs.rotation.radians) < tolerance
    }

    /// The value of a die tossed by hand. The local player's own die is rolled by its sheet,
    /// so the toss is a roll like any other: it shows in the dice overlay and is shared with
    /// the game. `nil` for any other die — the master tossing a player's die cannot roll that
    /// player's sheet — which then gets a value from the table alone.
    func rollTossedDie(_ dieId: EquipmentIdentifier) -> Int? {
        guard let mirroredSheet,
              let sheetDieId = mirroredSheet.dieIds[dieId],
              let value = diceRoot?.diceGameControllable.rollDie(
                  sheetDieId,
                  of: mirroredSheet.diceId,
                  networkActions: networkActions
              ) else { return nil }
        handTossedDice[dieId] = value
        return value
    }

    // MARK: - Die colors

    /// The d6 color of every pool slot this device can tell, from the dice sets it knows: the
    /// local seat's own focused set, the shared set of the player at any other seat, and the
    /// rolls of the guests. A die's color is the one its set has, so nothing is synced for it.
    func dieColors(focused: DiceModel?, shared: [DiceModel]) -> TableDieColors {
        func slots(of dice: DiceModel) -> [TableDieKind: [Int: String]] {
            TableDieColors.slots(
                dice: dice.dice.map { (sides: $0.die.max, colorCode: $0.colorCode) },
                poolSize: GameSetup.maxDicePerType
            )
        }
        var colors = TableDieColors()
        let localSeat = localSeat
        for seat in setup.seats where seat.id != PlayerSeat.guestSeat {
            if seat.id == localSeat {
                if let focused { colors.set(slots(of: focused), seat: seat.id.rawValue) }
            } else if let dice = (seatPlayerNames[seat.id] ?? []).lazy
                .compactMap({ name in shared.first { $0.name == name } }).first {
                colors.set(slots(of: dice), seat: seat.id.rawValue)
            }
        }
        var guestSlots: [TableDieKind: [Int: String]] = [:]
        for group in guestGroups {
            for die in group.dice where TableDieColors.isColored(die.kind) {
                guestSlots[die.kind, default: [:]][die.slot] = die.colorCode
            }
        }
        colors.set(guestSlots, seat: PlayerSeat.guestSeat.rawValue)
        return colors
    }

    /// Puts each colored die of the pools in its color. Runs on every device, as the color is a
    /// local material and not part of the synced die state; a slot with no color keeps the one it
    /// has, since it lies parked until a set claims it.
    func applyDieColors(_ colors: TableDieColors) {
        dieColorTask?.cancel()
        guard !colors.slots.isEmpty else { return }
        dieColorTask = Task { [weak self] in
            var materials: [TableDieKind: [String: PhysicallyBasedMaterial]] = [:]
            for (kind, bySeat) in colors.slots {
                for code in Set(bySeat.values.flatMap(\.values)) {
                    if let material = await Self.dieMaterial(for: kind, code: code) {
                        materials[kind, default: [:]][code] = material
                    }
                }
            }
            guard let self, !Task.isCancelled else { return }
            for seat in setup.seats {
                for (kind, bySeat) in colors.slots {
                    guard let slotColors = bySeat[seat.id.rawValue],
                          let dieIds = setup.dieIds(kind, seat: seat.id) else { continue }
                    for (slot, code) in slotColors where dieIds.indices.contains(slot) {
                        guard let material = materials[kind]?[code] else { continue }
                        apply(material: material, to: dieIds[slot], kind: kind)
                    }
                }
            }
        }
    }

    private static func dieMaterial(for kind: TableDieKind, code: String) async -> PhysicallyBasedMaterial? {
        switch kind {
            case .d6: await DieAssets.d6Material(for: code)
            case .d8: await Die8Assets.material(for: code)
            case .d3: await Die3Assets.material(for: code)
            case .d4: await Die4Assets.material(for: code)
            case .d12: await Die12Assets.material(for: code)
            case .d10: await Die10Assets.material(for: code)
            case .d20: await Die20Assets.material(for: code)
        }
    }

    private func apply(material: PhysicallyBasedMaterial, to dieId: EquipmentIdentifier, kind: TableDieKind) {
        switch kind {
            case .d6: tabletopGame.equipment(of: Die.self, matching: dieId)?.apply(material: material)
            case .d8: tabletopGame.equipment(of: Die8.self, matching: dieId)?.apply(material: material)
            case .d3: tabletopGame.equipment(of: Die3.self, matching: dieId)?.apply(material: material)
            case .d4: tabletopGame.equipment(of: Die4.self, matching: dieId)?.apply(material: material)
            case .d12: tabletopGame.equipment(of: Die12.self, matching: dieId)?.apply(material: material)
            case .d10: tabletopGame.equipment(of: Die10.self, matching: dieId)?.apply(material: material)
            case .d20: tabletopGame.equipment(of: Die20.self, matching: dieId)?.apply(material: material)
        }
    }

    /// Whether `dieId` belongs to the pool of the guest seat.
    func isGuestDie(_ dieId: EquipmentIdentifier) -> Bool {
        isDie(dieId, inPoolOf: PlayerSeat.guestSeat)
    }

    /// Whether `dieId` belongs to one of the table's dice pools.
    func isDie(_ dieId: EquipmentIdentifier) -> Bool {
        tabletopGame.equipment(of: Die20.self, matching: dieId) != nil
            || tabletopGame.equipment(of: Die3.self, matching: dieId) != nil
            || tabletopGame.equipment(of: Die4.self, matching: dieId) != nil
            || tabletopGame.equipment(of: Die12.self, matching: dieId) != nil
            || tabletopGame.equipment(of: Die10.self, matching: dieId) != nil
            || tabletopGame.equipment(of: Die8.self, matching: dieId) != nil
            || tabletopGame.equipment(of: Die.self, matching: dieId) != nil
    }

    /// Whether `dieId` belongs to a seat's pools.
    func isDie(_ dieId: EquipmentIdentifier, inPoolOf seat: TableSeatIdentifier) -> Bool {
        TableDieKind.allCases.contains { setup.dieIds($0, seat: seat)?.contains(dieId) == true }
    }

    /// The game master may handle any die; a player only the dice in their own seat's pool.
    /// Nobody handles the guest seat's dice: they mirror the rolls of players without a table,
    /// and a toss gave such a die a value of the table's own, which no longer matched that
    /// player's roll and hid their result on every table. See CODE_AUDIT_21 §5.11.
    func canControlDie(_ dieId: EquipmentIdentifier) -> Bool {
        guard !isGuestDie(dieId) else { return false }
        if isGameMaster { return true }
        guard let seat = localSeat else { return false }
        return isDie(dieId, inPoolOf: seat)
    }

    /// VoiceOver's "activate" gesture on a die entity (see `DiceComponent`, wired in `GameTableView`'s
    /// accessibility subscription) — the direct on-table toss gesture otherwise has no accessible
    /// equivalent. Picks a random result and applies it through the same `TabletopGame.addAction`
    /// path a physical toss uses.
    func tossDieForAccessibility(dieId: EquipmentIdentifier, sides: Int) {
        guard canControlDie(dieId) else { return }
        let result = rollTossedDie(dieId) ?? Int.random(in: 1...sides)
        if let equipment = tabletopGame.equipment(of: Die20.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        } else if let equipment = tabletopGame.equipment(of: Die3.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        } else if let equipment = tabletopGame.equipment(of: Die4.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        } else if let equipment = tabletopGame.equipment(of: Die12.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        } else if let equipment = tabletopGame.equipment(of: Die10.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        } else if let equipment = tabletopGame.equipment(of: Die8.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        } else if let equipment = tabletopGame.equipment(of: Die.self, matching: dieId) {
            tabletopGame.addAction(
                .updateEquipment(equipment, value: result, seatControl: nil, pose: nil, boundingBox: nil, context: 0)
            )
        }
    }
}
#endif
