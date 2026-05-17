// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit

struct GameInteraction: TabletopInteraction.Delegate {
    let game: GameTableModel
    
    @MainActor
    func updateCursor(_ proposedDestination: EquipmentIdentifier?, valid: Bool = false) {
        game.renderer.cursorTransform = nil
    }

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
    
    func onPhaseStarted(interaction: TabletopInteraction) {
        if game.tabletopGame.equipment(of: PlayerPawn.self, matching: interaction.value.startingEquipmentID) != nil {
        }

        if game.tabletopGame.equipment(of: Die.self, matching: interaction.value.startingEquipmentID) != nil {
            // Don't let the die land on any other equipment, just the table.
            interaction.setConfiguration(.init(allowedDestinations: .restricted([])))
        }
        
        // Monster pawns are restricted to GM control (set in MonsterPawn.initialState)
        // The seatControl property handles this automatically
        if game.tabletopGame.equipment(of: MonsterPawn.self, matching: interaction.value.startingEquipmentID) != nil {
            // Monsters can only be moved by GM, which is enforced by seatControl
            print("🐉 Monster pawn interaction started")
        }
    }
    
    func onGesturePhaseEnded(interaction: TabletopInteraction) {
        if let die = game.tabletopGame.equipment(of: Die.self, matching: interaction.value.startingEquipmentID) {
            // Play a sound when a player tosses a die.
            Task { @MainActor in
                if let audioLibraryComponent = die.entity.components[AudioLibraryComponent.self] {
                    if let soundResource = audioLibraryComponent.resources["dieSoundShort.mp3"] {
                        die.entity.playAudio(soundResource)
                    }
                }
            }
            // Pick a random value for the result of the die toss and toss the die.
            let nextValue = Int.random(in: 1 ... 6)
            interaction.addAction(.updateEquipment(die, value: nextValue))
            interaction.toss(equipmentID: interaction.value.startingEquipmentID, as: die.representation)
            // Move the die back to the starting pose on the table after toss animation finishes.
            interaction.addAction(.moveEquipment(matching: die.id, childOf: .tableID, pose: die.initialState.pose))
        }
        
        if let die20 = game.tabletopGame.equipment(of: Die20.self, matching: interaction.value.startingEquipmentID) {
            // Play a sound when a player tosses a die.
            Task { @MainActor in
                if let audioLibraryComponent = die20.entity.components[AudioLibraryComponent.self] {
                    if let soundResource = audioLibraryComponent.resources["dieSoundShort.mp3"] {
                        die20.entity.playAudio(soundResource)
                    }
                }
            }
            // Pick a random value for the result of the die toss and toss the die.
            let nextValue = Int.random(in: 1 ... 20)
            interaction.addAction(.updateEquipment(die20, value: nextValue))
            interaction.toss(equipmentID: interaction.value.startingEquipmentID, as: die20.representation)
            // Move the die back to the starting pose on the table after toss animation finishes.
            interaction.addAction(.moveEquipment(matching: die20.id, childOf: .tableID, pose: die20.initialState.pose))
        }
    }
    
    func onPhaseEnded(interaction: TabletopInteraction) {
        /* If there isn't a proposed destination, there's nothing to do here.
         Objects moving back to their original group animate there smoothly by default. */
        guard let dst = interaction.value.proposedDestination else {
            return
        }
        
        if let pawn = game.tabletopGame.equipment(of: PlayerPawn.self, matching: interaction.value.startingEquipmentID) {
            // Move the pawn to its new proposed destination with a default pose (centered in new destination).
            interaction.addAction(.moveEquipment(matching: pawn.id, childOf: dst.equipmentID, pose: .init()))
        }
        
        if let monsterPawn = game.tabletopGame.equipment(of: MonsterPawn.self, matching: interaction.value.startingEquipmentID) {
            // Move the monster pawn to its new position (GM only)
            interaction.addAction(.moveEquipment(matching: monsterPawn.id, childOf: dst.equipmentID, pose: .init()))
            print("🐉 Monster pawn moved by GM")
        }
    }
}

#endif
