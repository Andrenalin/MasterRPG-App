// @copyright André Trettin

import Combine
import SwiftUI

public extension View {
    func appExitNotifications(handler: @escaping @Sendable () async -> Void) -> some View {
        modifier(AppExitNotificationsViewModifier(resignHandler: handler))
    }
}

struct AppExitNotificationsViewModifier: ViewModifier {
    let resignHandler: @Sendable () async -> Void

    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        #if os(macOS)
            content
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification), perform: { _ in
                    Task {
                        await resignHandler()
                    }
                })
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification), perform: { _ in
                    Task {
                        await resignHandler()
                    }
                })
                .onReceive(timer) { _ in
                    Task {
                        await resignHandler()
                    }
                }
        #else
            content
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification), perform: { _ in
                    Task {
                        await resignHandler()
                    }
                })
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification), perform: { _ in
                    Task {
                        await resignHandler()
                    }
                })
                .onReceive(timer) { _ in
                    Task {
                        await resignHandler()
                    }
                }
        #endif
    }
}
