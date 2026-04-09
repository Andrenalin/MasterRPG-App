// @copyright André Trettin

import Observation

@MainActor @Observable
public final class AppGameStateModel: Sendable {
    public init() {}
    
    public var isGameRunning: Bool = false
    public var gameModus: GameModus = .edit
}
