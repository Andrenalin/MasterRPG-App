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
    
    public static func preview(isGameRunning: Bool) -> AppGameStateModel {
        AppGameStateModel(isGameRunning: isGameRunning)
    }
}
