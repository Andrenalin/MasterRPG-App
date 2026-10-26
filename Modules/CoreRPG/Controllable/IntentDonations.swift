// @copyright André Trettin

import Foundation
import os.log

#if !os(tvOS)
import AppIntents
#endif

/// Donates the intents behind what the user does in the UI, so Siri and Apple Intelligence learn
/// the app's usage patterns, and takes them back when the item they name is gone.
/// See CODE_AUDIT_AppIntents §4.4.
@MainActor
public enum IntentDonations {
#if !os(tvOS)
    /// How long an item stays selected before opening it counts as a deliberate open. A selection
    /// that changes sooner (arrow keys through a list, a quick tap-through) is not donated.
    public static let openDwell: Duration = .seconds(2)
    /// The same item is not donated again within this time, so toggling between two items does
    /// not repeat them.
    private static let repeatInterval: TimeInterval = 600

    private static var lastOpened: (itemId: UUID, date: Date)?

    /// Donates the open intent for `itemId` once the item has stayed selected for `openDwell`.
    /// Called from a `.task(id:)` that SwiftUI cancels when the selection changes, which is what
    /// ends the dwell early. `makeIntent` runs after the dwell and returns `nil` when the item
    /// is gone, so it should return the intent that matches the running OS.
    public static func donateOpen(of itemId: UUID, makeIntent: @MainActor () -> (any AppIntent)?) async {
        do {
            try await Task.sleep(for: openDwell)
        } catch {
            return
        }
        if let lastOpened, lastOpened.itemId == itemId,
           Date.now.timeIntervalSince(lastOpened.date) < repeatInterval {
            return
        }
        guard let intent = makeIntent() else { return }
        lastOpened = (itemId, .now)
        await donate(intent)
    }

    /// Donates an action the user just completed in the UI. The system already donates intents
    /// that Siri or Shortcuts ran, so this is only for the UI's own path to the same action.
    public static func donate(_ intent: some AppIntent) async {
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate \(String(describing: type(of: intent)), privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Deletes every donation that names `itemId`, so a trashed or purged item does not stay in
    /// the system's history of what the user did.
    public static func forget(itemId: UUID, module: NetworkModules) {
        guard let identifier = IntentEntityIdentifiers.identifier(for: itemId, module: module) else { return }
        if lastOpened?.itemId == itemId { lastOpened = nil }
        Task {
            do {
                try await IntentDonationManager.shared.deleteDonations(matching: .entityIdentifier(identifier))
            } catch {
                Logger.appIntents.debug("Failed to delete the donations of \(itemId, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }
    }
#else
    public static func forget(itemId: UUID, module: NetworkModules) {}
#endif
}
