// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import Foundation

/// What a module's root model tells Siri about the item the user is looking at: which entity it is
/// (on-screen awareness) and which open intent to donate. The activity annotation and the donation
/// flow are written once here; a module only supplies the two parts that name its own entity and
/// intent types. The requirements use public types only because some entity types are internal.
/// See CODE_AUDIT_AppIntents §9.4.
@MainActor
public protocol SiriItemContext: AnyObject {
    /// The entity identifier of `itemId`, or `nil` when the item must not be exposed (e.g. the
    /// rule compendium's own categories).
    func siriEntityIdentifier(for itemId: UUID) -> EntityIdentifier?

    /// The open intent that matches the running OS for `itemId`, or `nil` when the item is gone or
    /// not exposed.
    func siriOpenIntent(for itemId: UUID) -> (any AppIntent)?
}

public extension SiriItemContext {
    /// `appEntityIdentifier` is available since iOS 18.2 / macOS 15.2 / visionOS 2.2, so it needs no
    /// iOS 27 gate. See CODE_AUDIT_AppIntents §5.1.
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        activity.appEntityIdentifier = siriEntityIdentifier(for: itemId)
    }

    /// Donates the open intent that matches the running OS, once the item stays selected.
    /// See CODE_AUDIT_AppIntents §4.4.
    func donateSiriViewingIntent(for itemId: UUID) async {
        await IntentDonations.donateOpen(of: itemId) { [self] in siriOpenIntent(for: itemId) }
    }
}

#endif
