// @copyright André Trettin

import Foundation

/// Stable, window-level actions keep networking and persistence out of the
/// individual combatant rows.
public struct BattleRoundActions {
    public init(
        start: @escaping @MainActor () -> Void,
        end: @escaping @MainActor () -> Void,
        nextAttacker: @escaping @MainActor () -> Void,
        nextRound: @escaping @MainActor () -> Void,
        setInitiative: @escaping @MainActor (UUID, Int?) -> Void,
        adjustInitiative: @escaping @MainActor (UUID, Int) -> Void,
        setInitiativeOrder: @escaping @MainActor (BattleInitiativeOrder) -> Void,
        moveEntries: @escaping @MainActor (IndexSet, Int) -> Void,
        activateAttacker: @escaping @MainActor (UUID) -> Void,
        selectRollRecipient: @escaping @MainActor (UUID) -> Void,
        setDead: @escaping @MainActor (UUID, Bool) -> Void,
        assignCharacter: @escaping @MainActor (UUID, UUID) -> Void
    ) {
        self.start = start
        self.end = end
        self.nextAttacker = nextAttacker
        self.nextRound = nextRound
        self.setInitiative = setInitiative
        self.adjustInitiative = adjustInitiative
        self.setInitiativeOrder = setInitiativeOrder
        self.moveEntries = moveEntries
        self.activateAttacker = activateAttacker
        self.selectRollRecipient = selectRollRecipient
        self.setDead = setDead
        self.assignCharacter = assignCharacter
    }

    let start: @MainActor () -> Void
    let end: @MainActor () -> Void
    let nextAttacker: @MainActor () -> Void
    let nextRound: @MainActor () -> Void
    let setInitiative: @MainActor (UUID, Int?) -> Void
    let adjustInitiative: @MainActor (UUID, Int) -> Void
    let setInitiativeOrder: @MainActor (BattleInitiativeOrder) -> Void
    let moveEntries: @MainActor (IndexSet, Int) -> Void
    let activateAttacker: @MainActor (UUID) -> Void
    let selectRollRecipient: @MainActor (UUID) -> Void
    let setDead: @MainActor (UUID, Bool) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void
}
