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
    /// Delay between opening a window and performing a route on that window's navigator.
    static let crossWindowRouteDelay: Duration = .milliseconds(150)
}
