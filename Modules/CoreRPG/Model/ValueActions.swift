// @copyright André Trettin

import SwiftUI

/// What other modules may ask the Character module to do, like `MapActions` for the Map module
/// (Characters are `Value` items in code). Provided by the character root model.
public struct ValueActions: Equatable, Sendable {
    /// `id` should be stable across the writer's re-renders (e.g. the owning
    /// root model's `ObjectIdentifier`) so SwiftUI's environment diffing can
    /// skip invalidating readers when the same root writes the same
    /// functional closure again.
    public init(
        id: EnvironmentActionIdentity = .fresh(),
        quickCharacter: @MainActor @escaping @Sendable (String, UUID) async -> UUID?,
        cloneCharacter: @MainActor @escaping @Sendable (UUID, UUID) async -> UUID?
    ) {
        self.id = id
        self.quickCharacter = quickCharacter
        self.cloneCharacter = cloneCharacter
    }

    let id: EnvironmentActionIdentity
    /// Creates a saved Character with the given name and photo (name, photo id) and returns its id.
    public let quickCharacter: @MainActor @Sendable (String, UUID) async -> UUID?
    /// Duplicates a Character and gives the copy the photo (character id, photo id) and returns
    /// the copy's id; `nil` when the Character is gone or is not a single Character.
    public let cloneCharacter: @MainActor @Sendable (UUID, UUID) async -> UUID?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

public extension EnvironmentValues {
    // `.unconfigured`, not `.fresh()`: see `routeActions` (CODE_AUDIT §8.1).
    @Entry var valueActions: ValueActions = ValueActions(id: .unconfigured) { _, _ in nil } cloneCharacter: { _, _ in nil }
}
