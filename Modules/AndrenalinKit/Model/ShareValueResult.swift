// @copyright André Trettin

import SwiftUI

public struct ShareValueResult: Sendable {
    public init(networkActions: NetworkActions?, resultCategory: ResultCategory, showGame: Bool, gameModus: GameModus) {
        self.networkActions = networkActions
        self.resultCategory = resultCategory
        self.showGame = showGame
        self.gameModus = gameModus
    }

    public let networkActions: NetworkActions?
    public let resultCategory: ResultCategory
    public let showGame: Bool
    public let gameModus: GameModus
    
    @MainActor
    public static func preview(showGame: Bool = true) -> ShareValueResult { ShareValueResult(networkActions: .empty, resultCategory: ResultCategory(id: UUID(), module: .none), showGame: showGame, gameModus: .edit) }
    
    public static let empty = ShareValueResult(networkActions: nil, resultCategory: ResultCategory(id: UUID(), module: .none), showGame: false, gameModus: .edit)
}

public extension EnvironmentValues {
    @Entry var shareResult: ShareValueResult = .empty
}
