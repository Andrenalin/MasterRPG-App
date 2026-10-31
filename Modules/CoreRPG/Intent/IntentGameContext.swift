// @copyright André Trettin

import Foundation

/// The running game as the module intents see it. The modules cannot import GameRPG (it imports
/// them), so RolePlayGameKit sets `networkActions` once at launch; an intent that does what a game
/// screen does (a dice roll) shares its result through the same actions the screen gets from the
/// environment. `nil` while no game runs. See CODE_AUDIT_AppIntents3 §5.3.
@MainActor
public enum IntentGameContext {
    public static var networkActions: @MainActor () -> NetworkActions? = { nil }
    /// Whether this device runs the game as master or player; `nil` while no game runs.
    public static var gameModus: @MainActor () -> GameModus? = { nil }
    /// The supporter tier a player joins with, as the join screen reads it from the environment.
    public static var supporterTier: @MainActor () -> SupporterTier = { .none }
    /// Sets the app's game flags as the game screens do, for an intent that joins or ends a game
    /// while no game screen is on screen to follow `gameConfig.state`.
    public static var setGameState: @MainActor (_ isRunning: Bool, _ modus: GameModus) -> Void = { _, _ in }
    /// Hands the turn of the running battle to the next combatant, on the game master's device.
    /// For the Control Center control (`NextTurnControlIntent`), which cannot reach GameRPG.
    public static var nextTurn: @MainActor () -> Void = {}
}
