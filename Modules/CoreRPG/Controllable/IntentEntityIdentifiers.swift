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
    private struct Registration: Sendable {
        let identifier: @Sendable (UUID) -> EntityIdentifier
        let removeFromIndex: @Sendable ([UUID]) async -> Void
    }

    private static let registrations = OSAllocatedUnfairLock<[NetworkModules: Registration]>(initialState: [:])

    public static func register<Entity: IndexedEntity>(_ entityType: Entity.Type, for module: NetworkModules) where Entity.ID == UUID {
        let registration = Registration(
            identifier: { EntityIdentifier(for: entityType, identifier: $0) },
            removeFromIndex: { await deleteIntentEntities(ids: $0, ofType: entityType) }
        )
        registrations.withLock { $0[module] = registration }
    }

    /// The identifier of the entity for `itemId`, or `nil` when the module has not registered one.
    public static func identifier(for itemId: UUID, module: NetworkModules) -> EntityIdentifier? {
        registrations.withLock { $0[module] }?.identifier(itemId)
    }

    /// Takes the items out of the module's App Entity index, for items trashed or purged in the UI.
    /// See CODE_AUDIT_AppIntents §5.3.
    public static func removeFromIndex(itemIds: [UUID], module: NetworkModules) async {
        guard let registration = registrations.withLock({ $0[module] }) else { return }
        await registration.removeFromIndex(itemIds)
    }
}
#endif
