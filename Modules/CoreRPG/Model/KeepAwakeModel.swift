// @copyright André Trettin

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Keeps the screen from locking while at least one owner needs it.
///
/// `UIApplication.isIdleTimerDisabled` is one flag for the whole app. A running game and an
/// object capture used to set and clear it on their own, so leaving a capture screen switched
/// auto-lock back on under a running game, and stopping the game did the same to a capture. Each
/// owner now holds its own claim and the flag follows the union. See CODE_AUDIT §3.2.
@MainActor
public final class KeepAwakeModel {
    public enum Owner: Hashable, Sendable, CaseIterable {
        case game
        case capture
        case reconstruction
    }

    /// The model every screen of the app shares.
    public static let shared = KeepAwakeModel()

    /// `apply` receives `true` when the first owner arrives and `false` when the last one leaves;
    /// it is not called while the state stays the same.
    public init(apply: @escaping @MainActor (Bool) -> Void = KeepAwakeModel.applyToApplication) {
        self.apply = apply
    }

    public var isKeepingAwake: Bool { !owners.isEmpty }

    public func acquire(_ owner: Owner) {
        let wasKeepingAwake = isKeepingAwake
        owners.insert(owner)
        if !wasKeepingAwake { apply(true) }
    }

    public func release(_ owner: Owner) {
        guard owners.remove(owner) != nil else { return }
        if !isKeepingAwake { apply(false) }
    }

    private var owners: Set<Owner> = []
    private let apply: @MainActor (Bool) -> Void

    @MainActor
    public static func applyToApplication(_ keepsAwake: Bool) {
#if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.isIdleTimerDisabled = keepsAwake
#elseif os(macOS)
        // macOS has no idle timer flag: a process activity keeps the display from sleeping
        // while a game runs. See CODE_AUDIT_26 §5.58.
        if keepsAwake {
            guard displayActivity == nil else { return }
            displayActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated],
                reason: "A game is running"
            )
        } else if let displayActivity {
            ProcessInfo.processInfo.endActivity(displayActivity)
            Self.displayActivity = nil
        }
#endif
    }

#if os(macOS)
    @MainActor private static var displayActivity: NSObjectProtocol?
#endif
}
