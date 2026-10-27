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

    /// The same repeatable action (a dice roll) is not donated again within this time.
    private static let repeatedActionInterval: TimeInterval = 300

    private static var lastDonated: [UUID: Date] = [:]

    /// Donates an action the user repeats often, such as a dice roll, at most once per
    /// `repeatedActionInterval` for the same item, so a combat round does not flood the system.
    /// `makeIntent` runs only when the donation goes out. See CODE_AUDIT_AppIntents2 §5.5.
    public static func donateThrottled(for itemId: UUID, makeIntent: @MainActor () -> (any AppIntent)?) async {
        if let last = lastDonated[itemId], Date.now.timeIntervalSince(last) < repeatedActionInterval {
            return
        }
        guard let intent = makeIntent() else { return }
        lastDonated[itemId] = .now
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

    /// Takes an item that was trashed or purged out of what Siri knows: its donations and its entry
    /// in the App Entity index. Without this a trashed item stays in the system's history and
    /// remains findable. See CODE_AUDIT_AppIntents §4.4, §5.3.
    public static func forget(itemId: UUID, module: NetworkModules) {
        guard let identifier = IntentEntityIdentifiers.identifier(for: itemId, module: module) else { return }
        if lastOpened?.itemId == itemId { lastOpened = nil }
        lastDonated[itemId] = nil
        Task {
            await IntentEntityIdentifiers.removeFromIndex(itemIds: [itemId], module: module)
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
