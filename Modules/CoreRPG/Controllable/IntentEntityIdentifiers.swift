// @copyright André Trettin

import Foundation
import os

#if !os(tvOS)
import AppIntents

/// Which `AppEntity` type each module's items are exposed as, registered by the modules at launch
/// (CoreRPG cannot see their entity types). Donations, the delete-on-trash cleanup and the list
/// row annotations build an `EntityIdentifier` from it. Not main-actor isolated, because SwiftUI
/// asks for annotations from its own closures. See CODE_AUDIT_AppIntents §4.4, §4.7.
public enum IntentEntityIdentifiers {
    private static let makers = OSAllocatedUnfairLock<[NetworkModules: @Sendable (UUID) -> EntityIdentifier]>(initialState: [:])

    public static func register<Entity: AppEntity>(_ entityType: Entity.Type, for module: NetworkModules) where Entity.ID == UUID {
        makers.withLock { $0[module] = { EntityIdentifier(for: entityType, identifier: $0) } }
    }

    /// The identifier of the entity for `itemId`, or `nil` when the module has not registered one.
    public static func identifier(for itemId: UUID, module: NetworkModules) -> EntityIdentifier? {
        makers.withLock { $0[module] }?(itemId)
    }
}
#endif
