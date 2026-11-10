// @copyright André Trettin

import Foundation
import SwiftUI

/// Creates a temporary map from a photo and shows it to the players. The game provides it
/// (the game master only, while a game runs); everywhere else it stays disabled and the photo
/// list offers no such action. The map lives in game memory only and is gone with the game.
public struct GenerateMapAction: Sendable, Equatable {
    /// `id` should be stable across the writer's re-renders so SwiftUI's environment diffing can
    /// skip invalidating readers when the same writer re-supplies the same closure. `isEnabled`
    /// is compared separately since it is state readers need to observe.
    public init(
        id: EnvironmentActionIdentity = .fresh(),
        isEnabled: Bool = true,
        generate: @MainActor @escaping @Sendable (UUID) -> Void
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.generate = generate
    }

    let id: EnvironmentActionIdentity
    public let isEnabled: Bool
    private let generate: @MainActor @Sendable (UUID) -> Void

    /// - Parameter photoId: The photo that becomes the map's background.
    @MainActor
    public func callAsFunction(photoId: UUID) {
        guard isEnabled else { return }
        generate(photoId)
    }

    public static let disabled = GenerateMapAction(id: .unconfigured, isEnabled: false) { _ in }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.isEnabled == rhs.isEnabled
    }
}

public extension EnvironmentValues {
    @Entry var generateMapAction: GenerateMapAction = .disabled
}
