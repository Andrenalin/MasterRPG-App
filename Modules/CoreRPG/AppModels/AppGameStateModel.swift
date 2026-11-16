// @copyright André Trettin

import Observation

@MainActor @Observable
public final class AppGameStateModel: Sendable {
    public init(isGameRunning: Bool = false, gameModus: GameModus = .edit) {
        self.isGameRunning = isGameRunning
        self.gameModus = gameModus
    }
        
    public var isGameRunning: Bool
    public var gameModus: GameModus
    
    /// Maps the state of the running game to the two fields. Assigns a field only when it
    /// changes, so readers of the other one are not invalidated. See CODE_AUDIT_26 §9.33.
    public func update(isRunning: Bool, isMaster: Bool) {
        if isGameRunning != isRunning {
            isGameRunning = isRunning
        }
        let newModus: GameModus = isRunning ? (isMaster ? .master : .player) : .edit
        if gameModus != newModus {
            gameModus = newModus
        }
    }

    public static func preview(isGameRunning: Bool) -> AppGameStateModel {
        AppGameStateModel(isGameRunning: isGameRunning)
    }
}
