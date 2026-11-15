//
//  NavigationConfiguration.swift
//  Navigator
//
//  Created by Michael Long on 12/1/24.
//

import SwiftUI
import os.log

/// Configuration options for Navigator.
///
/// Allows the developer to modify some of Navigator's basic behavior by configuring and installing a
/// root Navigator in the application's navigation tree.
///
/// The root navigator is managed and can present sheets and covers from the root view if needed.
/// ```swift
/// @main
/// struct NavigatorDemoApp: App {
///     let navigator = Navigator(configuration: .init(restorationKey: "1.0.0", autoDestinationMode: true)
///     var body: some Scene {
///         WindowGroup {
///             RootTabView()
///                 .navigationAutoReceive(AppRootDestinations.self)
///                 .navigationRoot(navigator)
///         }
///     }
/// }
/// ```
nonisolated public struct NavigationConfiguration {

    /// Determines whether or not users should see animation steps when deep linking.
    ///
    /// Set value to 0.0 for maximum animation speed. Longer (0.5) to let the user see the distinct "steps" involved in navigating
    /// to a new destination. Default is 0.1.
    public let executionDelay: TimeInterval

    /// Provide a restorationKey to enable state restoration in named ManagedNavigationControllers.
    ///
    /// Increment or change the key when changing destination types.
    ///
    /// If no restorationKey is provided then navigation state restoration is disabled.
    public let restorationKey: String?

    /// Allows the developer to log navigation messages to the console or to their own logging system.
    ///
    /// If logger is nil then nothing is logged.
    public let logger: ((_ event: NavigationEvent) -> Void)?

    /// Logging verbosity
    public let verbosity: NavigationEvent.Verbosity

    /// AutoDestinationMode
    public let autoDestinationMode: Bool

    /// Creates a new navigation configuration.
    ///
    /// - Parameters:
    ///   - restorationKey: An optional key used to enable state restoration
    ///     for named managed navigation stacks. Change the key when you add
    ///     or remove destination types.
    ///   - logger: A closure that receives navigation events for logging.
    ///     The default implementation prints events in debug builds.
    ///   - executionDelay: Controls the timing of deep-link animations.
    ///     Smaller values speed up multi-step navigation; larger values make
    ///     each step more visible.
    ///   - verbosity: Controls which events are emitted by the logger.
    ///   - autoDestinationMode: When enabled, allows navigation to
    ///     ``NavigationDestination`` values without explicit registration.
    public init(
        restorationKey: String? = nil,
        logger: ((NavigationEvent) -> Void)? = {
            // Uses the project's `Logger` conventions rather than a bare
            // `print`, so navigation events are filterable/redactable like
            // every other subsystem's logging. See CODE_AUDIT §5.5.
            #if DEBUG
            // Destinations and routes can carry item names; never public. See CODE_AUDIT_26 §6.11.
            Logger.navigation.debug("\($0.description, privacy: .private)")
            #endif
        },
        executionDelay: TimeInterval = 0.3,
        verbosity: NavigationEvent.Verbosity = .warning,
        autoDestinationMode: Bool = true
    ) {
        // iOS 18 is below this project's iOS 26.0 deployment floor, so the
        // pre-iOS-18 branch this once guarded (a 0.7 floor) could never run —
        // collapsed to just the reachable branch. See CODE_AUDIT_10 §3.2.
        self.executionDelay = min(max(0.3, executionDelay), 5.0)
        self.restorationKey = restorationKey
        self.logger = logger
        self.verbosity = verbosity
        self.autoDestinationMode = autoDestinationMode
    }

}

extension View {
    /// Allows the developer to modify some of Navigator's basic behavior by configuring and installing a
    /// root Navigator in the application's navigation tree.
    ///
    /// This modifier is managed and can present sheets and covers from the root view if needed.
    /// ```swift
    /// @main
    /// struct NavigatorDemoApp: App {
    ///     let navigator = Navigator(configuration: .init(restorationKey: "1.0.0", verbosity: .info)
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             RootTabView()
    ///                 .navigationAutoReceive(AppRootDestinations.self)
    ///                 .navigationRoot(navigator)
    ///         }
    ///     }
    /// }
    /// ```
    public func navigationRoot(_ navigator: Navigator) -> some View {
        self.modifier(NavigationRootModifier(navigator: navigator))
    }
}

private struct NavigationRootModifier: ViewModifier {

    var navigator: Navigator

    public func body(content: Content) -> some View {
        content
            .modifier(NavigationPresentationModifiers(navigator: navigator))
            .environment(\.navigator, navigator)
    }

}
