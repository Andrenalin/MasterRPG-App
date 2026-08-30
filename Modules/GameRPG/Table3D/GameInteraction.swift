// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit

struct GameInteraction: @MainActor TabletopInteraction.Delegate {
    let game: GameTableModel

    @MainActor
    mutating func update(interaction: TabletopKit.TabletopInteraction) {
        var destination = interaction.value.proposedDestination?.equipmentID

        if interaction.value.phase == .started {
            onPhaseStarted(interaction: interaction)
        }

        if interaction.value.gesture?.phase == .ended {
            onGesturePhaseEnded(interaction: interaction)
        }

        if interaction.value.phase == .ended {
            destination = nil
            onPhaseEnded(interaction: interaction)
        }

        // `interaction.value.pose` is the live table-space pose of the
        // dragged equipment — exactly where it would land right now — so
        // it doubles as the cursor's preview position/orientation while a
        // destination is proposed. Previously this always passed `nil`,
        // so the cursor mesh (built in `GameRenderer`) never rendered.
        // See CODE_AUDIT_9 §5.2.
        let cursorTransform = destination != nil ? interaction.value.pose.cursorTransform : nil
        game.renderer.updateCursor(cursorTransform)
    }

    @MainActor
    func onPhaseStarted(interaction: TabletopInteraction) {
        if game.tabletopGame.equipment(
            of: Die20.self,
            matching: interaction.value.startingEquipmentID
        ) != nil {
            // Don't let the die land on any other equipment, just the table.
            interaction.setConfiguration(.init(allowedDestinations: .restricted([])))
        }

    }

    @MainActor
    func onGesturePhaseEnded(interaction: TabletopInteraction) {
        if let die20 = game.tabletopGame.equipment(of: Die20.self, matching: interaction.value.startingEquipmentID) {
            // Only start the toss here — don't set `value`/`pose` yet. Doing
            // that synchronously at gesture-end, before the toss has even
            // started simulating, raced the physics animation that
            // `.toss(...)` itself was just about to start: the die would jump
            // to whatever pose we forced instead of playing out the toss,
            // producing exactly the symptoms this went through — flying off,
            // resting 20-50 cm above the table, disappearing, or (with two
            // dice) settling at two different heights, since each die's
            // forced pose competed with the simulation's own, unpredictably.
            // Apple's own TabletopKit dice sample (`DiceInteraction.swift`,
            // via the `tabletopkit-simulating-dice-rolls-as-a-component-for-
            // your-game` sample) makes the same split: `.toss(...)` here, and
            // the final `.updateEquipment(...)` only once
            // `onTossStart(interaction:outcomes:)` below reports where the
            // simulation actually left the die.
            interaction.toss(equipmentID: interaction.value.startingEquipmentID, as: die20.representation)
        }
    }

    /// Fires once each tossed die's physics simulation has a final resting
    /// outcome. `outcome.pose` is that simulation's own result — the die's
    /// actual final table-space position/rotation, not a value we compute or
    /// guess — so setting it here is what makes the die retain that resting
    /// state once the simulation ends, exactly as this delegate method's own
    /// documentation describes. This project still picks its own random
    /// face value here (rather than reading it back off
    /// `outcome.restingOrientation`) the same way Apple's sample's own
    /// `predeterminedOutcome` branch does — only the *pose* has to come from
    /// the simulation; the face shown is this game's own concern.
    @MainActor
    func onTossStart(interaction: TabletopInteraction, outcomes: [TabletopInteraction.TossOutcome]) {
        for outcome in outcomes {
            guard let die20 = game.tabletopGame.equipment(of: Die20.self, matching: outcome.id) else { continue }
            let nextValue = Int.random(in: 1 ... 20)
            interaction.addAction(.updateEquipment(die20, value: nextValue, pose: outcome.pose))
        }
    }

    @MainActor
    func onPhaseEnded(interaction: TabletopInteraction) {
        /* If there isn't a proposed destination, there's nothing to do here.
         Objects moving back to their original group animate there smoothly by default. */
        guard interaction.value.proposedDestination != nil else {
            return
        }
        // Pins are plain entities driven by mapState, not TabletopKit
        // equipment — dice are the only draggable equipment left.
    }
}

#endif
