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
