// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit

struct GameInteraction: @MainActor TabletopInteraction.Delegate {
    let game: GameTableModel

    /// Only a die's owner (or the game master) may pick it up and toss it; everyone else's dice are
    /// read-only mirrors of that player's character-sheet roll.
    @MainActor
    func shouldAcceptInteraction(
        initialValue: TabletopInteraction.Value,
        handoffValue: TabletopInteraction.Value?
    ) -> TabletopInteraction.NewInteractionIntent {
        guard handoffValue == nil else { return .reject }
        let equipmentId = initialValue.startingEquipmentID
        if game.isDie(equipmentId), !game.canControlDie(equipmentId) {
            return .reject
        }
        return .acceptWithConfiguration(.init(allowedDestinations: .any))
    }

    @MainActor
    mutating func update(interaction: TabletopKit.TabletopInteraction) {
        if interaction.value.phase == .started {
            onPhaseStarted(interaction: interaction)
        }

        if interaction.value.gesture?.phase == .ended {
            onGesturePhaseEnded(interaction: interaction)
        }

        // `interaction.value.pose` is the live table-space pose of the dragged equipment — exactly
        // where it would land right now — so it doubles as the cursor's preview position/orientation
        // while a destination is proposed.
        let hasDestination = interaction.value.phase != .ended && interaction.value.proposedDestination != nil
        game.renderer.updateCursor(hasDestination ? interaction.value.pose.cursorTransform : nil)
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
            // Only start the toss here — don't set `value`/`pose` yet. Forcing them synchronously at
            // gesture end raced the physics animation `.toss(...)` was about to start: the die would
            // jump to the forced pose instead of playing out the toss. Apple's TabletopKit dice
            // sample makes the same split: `.toss(...)` here, and the final `.updateEquipment(...)`
            // only once `onTossStart(interaction:outcomes:)` reports where the simulation left the die.
            interaction.toss(equipmentID: interaction.value.startingEquipmentID, as: die20.representation)
        }
    }

    /// Fires once each tossed die's physics simulation has a final resting outcome. `outcome.pose` is
    /// the simulation's own result — the die's actual final table-space position/rotation — so
    /// setting it here is what makes the die retain that resting state. The face value is this
    /// game's own concern, so it is picked here rather than read off `outcome.restingOrientation`:
    /// the player's sheet rolls its own die (`GameTableModel.rollTossedDie`).
    @MainActor
    func onTossStart(interaction: TabletopInteraction, outcomes: [TabletopInteraction.TossOutcome]) {
        for outcome in outcomes {
            guard let die20 = game.tabletopGame.equipment(of: Die20.self, matching: outcome.id) else { continue }
            let nextValue = game.rollTossedDie(outcome.id) ?? Int.random(in: 1 ... 20)
            interaction.addAction(.updateEquipment(die20, value: nextValue, pose: outcome.pose))
        }
    }
}

#endif
