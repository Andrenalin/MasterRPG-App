// @copyright André Trettin

import SwiftUI

public enum GameModus: Int, Hashable, CaseIterable, Codable, Sendable {
    case edit = 0
    case master = 1
    case player = 2
}

public extension EnvironmentValues {
    @Entry var gameModus: GameModus = .edit
}

public struct ShowGameActions: Sendable {
    public let show: @MainActor @Sendable (Bool) -> Void

    public init(show: @MainActor @escaping @Sendable (Bool) -> Void) {
        self.show = show
    }
}

public extension EnvironmentValues {
    @Entry var showGame: Bool = false
}

public extension EnvironmentValues {
    var showGameActions: ShowGameActions {
        get { self[ShowGameActionsKey.self] }
        set { self[ShowGameActionsKey.self] = newValue }
    }
}

struct ShowGameActionsKey: EnvironmentKey {
    static let defaultValue = ShowGameActions(show: { _ in })
}
