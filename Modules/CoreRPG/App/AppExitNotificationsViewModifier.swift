// @copyright André Trettin

import SwiftUI

public extension View {
    func appExitNotifications(handler: @escaping @Sendable () async -> Void) -> some View {
        modifier(AppExitNotificationsViewModifier(resignHandler: handler))
    }
}

struct AppExitNotificationsViewModifier: ViewModifier {
    let resignHandler: @Sendable () async -> Void

    /// How long each individual sleep in the periodic-housekeeping `.task` below
    /// lasts. Not tied to app-exit notification delivery, just a fallback safety
    /// net independent of it.
    private static let periodicHousekeepingInterval: Duration = .seconds(60)

    func body(content: Content) -> some View {
        #if os(macOS)
            content
                .task {
                    for await _ in NotificationCenter.default.notifications(named: NSApplication.willTerminateNotification) {
                        await resignHandler()
                    }
                }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: NSApplication.willResignActiveNotification) {
                        await resignHandler()
                    }
                }
                .task {
                    await runPeriodicHousekeeping()
                }
        #else
            content
                .task {
                    for await _ in NotificationCenter.default.notifications(named: UIApplication.willResignActiveNotification) {
                        await resignHandler()
                    }
                }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: UIApplication.willTerminateNotification) {
                        await resignHandler()
                    }
                }
                .task {
                    await runPeriodicHousekeeping()
                }
        #endif
    }

    /// Replaces a `Timer.publish`/Combine subscription with a cancellable
    /// `Task`-based sleep loop — SwiftUI's `.task` cancels it automatically when
    /// the view disappears, same lifecycle the Combine subscription had. See
    /// CODE_AUDIT_9 §4.2.
    private func runPeriodicHousekeeping() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.periodicHousekeepingInterval)
            guard !Task.isCancelled else { return }
            await resignHandler()
        }
    }
}
