// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit

struct GameInteraction: @MainActor TabletopInteraction.Delegate {
    let game: GameTableModel

    @MainActor
    func updateCursor(_ proposedDestination: EquipmentIdentifier?, valid: Bool = false) {
        game.renderer.cursorTransform = nil
    }

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

        game.renderer.updateCursor(destination)
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
            // Pick a random value for the result of the die toss and toss the die.
            let nextValue = Int.random(in: 1 ... 20)
            interaction.addAction(.updateEquipment(die20, value: nextValue))
            interaction.toss(equipmentID: interaction.value.startingEquipmentID, as: die20.representation)
            // Move the die back to its actual current-layout pose on the table after
            // the toss animation finishes. `landingPose` itself: Apple's own
            // TabletopKit sample uses `die.initialState.pose` here directly — safe
            // for their single die, permanently fixed to one slot, but
            // `die20.initialState.pose` here is frozen at equipment-creation time
            // from `GameSetup`'s full pre-allocated pool layout, which
            // `GameTableModel.applyDiceRoll` supersedes with a tighter,
            // currently-active layout whenever the focused dice set changes.
            // `game.homePoseByDieId` tracks that supersession — see its own doc for
            // why this has to be plain, synchronous local state rather than a live
            // TabletopKit snapshot read from inside this delegate's own
            // gesture-phase callbacks (tried that; it caught the die mid-motion and
            // sent it flying instead).
            let landingPose = game.homePoseByDieId[die20.id] ?? die20.initialState.pose
            // `.updateEquipment(pose:)`, not `.moveEquipment(childOf:pose:)` (which
            // Apple's sample uses, and which this file used until now): the die
            // never actually changes parent — it's restricted to the table alone by
            // `onPhaseStarted`'s `allowedDestinations` above — so re-parenting to
            // `.tableID` it's already a child of is unnecessary, and `.moveEquipment`
            // was resting the die roughly 40-50 cm above the table's true surface
            // after the toss, unlike `.updateEquipment(pose:)`, which is the exact
            // action `applyDiceRoll` already uses to place this same die correctly at
            // rest. The two actions apparently derive resting height differently;
            // reusing the confirmed-correct one instead of guessing further at why
            // `.moveEquipment`'s differs.
            interaction.addAction(.updateEquipment(die20, pose: landingPose))
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
