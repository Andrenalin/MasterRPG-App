// @copyright André Trettin

import SwiftUI

public extension EnvironmentValues {
    @Entry var shareResult: ShareValueResult = .empty
}

public struct ShareValueResult: Sendable {
    public init(networkActions: NetworkActions?, resultCategory: ResultCategory, showGame: Bool) {
        self.networkActions = networkActions
        self.resultCategory = resultCategory
        self.showGame = showGame
    }

    public let networkActions: NetworkActions?
    public let resultCategory: ResultCategory
    public let showGame: Bool
    
    @MainActor
    public static func preview(showGame: Bool = true) -> ShareValueResult { ShareValueResult(networkActions: .empty, resultCategory: ResultCategory(id: UUID(), module: .none), showGame: showGame) }
    
    public static let empty = ShareValueResult(networkActions: nil, resultCategory: ResultCategory(id: UUID(), module: .none), showGame: false)
}
