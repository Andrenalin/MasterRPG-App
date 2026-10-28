// @copyright André Trettin

import Foundation

/// Heuristic delays used by deep-link routing across windows.
///
/// **Why:** When a route opens a new window, the route can't be delivered immediately —
/// the Navigator inside the new scene needs a moment to mount and subscribe to its publisher.
/// Performing the route synchronously drops it on the floor. We can't wait on
/// `ScenesManager.getSceneState == .opened` instead, because (a) on macOS the SwiftUI
/// Settings window is not tracked by ScenesManager, and (b) the scene being onscreen
/// doesn't guarantee its Navigator has subscribed yet.
enum NavigationTiming {
    /// Settle delay between two steps of one navigation sequence (e.g. presenting Settings,
    /// then its import cover). Routes into a window that is still opening no longer use it:
    /// the navigator buffers sends until a receiver mounts. See CODE_AUDIT_18 §3.17.
    static let crossWindowRouteDelay: Duration = .milliseconds(150)

    /// Delay between switching tabs/columns and delivering a route to the newly selected
    /// module's navigator, for the same reason as `crossWindowRouteDelay`: the destination
    /// `ManagedNavigationStack` needs a moment to mount and subscribe after becoming selected.
    static let tabSwitchMountDelay: TimeInterval = 0.8

    /// Delay between a size-class change and restoring the remembered module and item in the
    /// layout that replaced the old one (`TabRootView`), so the new layout has settled first. The
    /// navigator buffers a route no receiver takes, so a signal from the new layout could replace
    /// this delay, but that has to be tried on a device first. See CODE_AUDIT_Since_3.0.1 §8.2.
    static let layoutChangeSettleDelay: Duration = .milliseconds(200)
}
