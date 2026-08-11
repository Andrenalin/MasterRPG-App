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
            // Move the die back to the starting pose on the table after toss animation finishes.
            interaction.addAction(.moveEquipment(matching: die20.id, childOf: .tableID, pose: die20.initialState.pose))
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
