//
//  NavigationSend.swift
//  Navigator
//
//  Created by Michael Long on 11/14/24.
//

import Combine
import SwiftUI

/// A type that can broadcast hashable values through the navigation system.
///
/// Conforming types are responsible for delivering values to registered
/// `onNavigationReceive` handlers, enabling features such as deep linking
/// and cross-tree coordination.
public protocol NavigationSending {
    /// Sends an ordered list of values to navigation receivers.
    ///
    /// - Parameter values: The values to broadcast. Each value will be
    ///   matched against registered receive handlers.
    @MainActor func send(values: [any Hashable])
}

extension NavigationSending {
    /// Sends a value or values to navigation receivers throughout the application.
    ///
    /// This is the core functionality behind deep linking support in Navigator.
    ///
    /// The primary difference between this and `navigate(to:)` is that you don't need to know what navigator is handling
    /// the request, nor does the value need to be of type ``NavigationDestination``.
    ///
    /// They just need to be `Hashable`.
    ///
    /// ### Sending Values
    /// The following code broadcasts a list of actions to be handled somewhere in the application. First it selects the Home tab,
    /// then navigates to Page 2.
    /// ```swift
    /// Button("Go To Tab Home, Page 2") {
    ///     navigator.send(
    ///         RootTabs.home,
    ///         HomeDestinations.page2
    ///     )
    /// }
    /// ```
    /// ### Receiving Values
    /// Receiving values is simple. Just register a receive handler for the desired type.
    /// ```swift
    /// .onNavigationReceive { (tab: RootTabs) in
    ///     if tab == selectedTab {
    ///         return .immediately
    ///     }
    ///     selectedTab = tab
    ///     return .auto
    /// }
    /// ```
    /// And then perform whatever action is needed on receipt.
    ///
    /// Here's the handler for `HomeDestinations`.`
    /// ```swift
    /// .onNavigationReceive { (destination: HomeDestinations, navigator) in
    ///     navigator.navigate(to: destination)
    ///     return .auto
    /// }
    /// ```
    ///
    /// Speaking of which, receive handlers return a value of type ``NavigationReceiveResumeType``, which tells Navigator how to
    /// process the remaining values in the queue. Additional values can be paused, cancelled, or simply processed normally.
    ///
    /// Note that there should be one and only one registered handler for a given type in the navigation tree. If more than
    /// one exists the first handler will consume the value and the remaining handlers should be ignored.
    @MainActor
    public func send(_ values: any Hashable...) {
        send(values: values)
    }
}

extension Navigator: NavigationSending {

    /// Core implementation for broadcasting one or more values to navigation receivers.
    ///
    /// Most callers should prefer the variadic ``NavigationSending/send(_:)``
    /// convenience API, which forwards to this method.
    @MainActor
    public func send(values: [any Hashable]) {
        send(values: values, firstStashedAt: nil)
    }

    /// `firstStashedAt` carries a replayed send's original stash time, so an unconsumed replay
    /// keeps its lifetime instead of restarting it. See CODE_AUDIT_19 §3.2.
    @MainActor
    internal func send(values: [any Hashable], firstStashedAt: ContinuousClock.Instant?) {
        guard let value: any Hashable = values.first else {
            return
        }
        let remainingValues = Array(values.dropFirst())
        if let action = value as? NavigationAction {
            log(.send(.performing(action)))
            resume(action(self), values: remainingValues)
        } else {
            log(.send(.sending(value)))
            publisher.send(NavigationSendValues(navigator: root, value: value, values: remainingValues, firstStashedAt: firstStashedAt))
        }
    }

    @MainActor
    internal func resume(_ action: NavigationReceiveResumeType, values: [any Hashable] = [], delay: TimeInterval? = nil) {
        switch action {
        case .auto:
            let delay: TimeInterval = delay ?? executionDelay
            resumeTask?.cancel()
            resumeTask = delayedTask(.seconds(delay)) { [weak self] in
                self?.send(values: values)
            }
        case .immediately:
            send(values: values)
        case .after(let interval):
            resume(.auto, values: values, delay: interval)
        case .inserting(let newValues):
            resume(.immediately, values: newValues + values)
        case .appending(let newValues):
            resume(.immediately, values: values + newValues)
        case .replacing(let newValues):
            resume(.immediately, values: newValues)
        case .cancel:
            break
        }
    }

}

extension View {

    /// Handler receives values of a specific type broadcast via `navigator.send`.
    /// ```swift
    /// .onNavigationReceive { (tab: RootTabs) in
    ///     if tab == selectedTab {
    ///         return .immediately
    ///     }
    ///     selectedTab = tab
    ///     return .auto
    /// }
    /// ```
    /// Receive handlers return a value of type ``NavigationReceiveResumeType``. That tells Navigator how to process the remaining
    /// values in the queue.
    ///
    /// Note that there should be one and only one registered handler for a given type in the navigation tree. If more than
    /// one exists the first handler will consume the value and the remaining handlers should be ignored.
    public func onNavigationReceive<T: Hashable>(handler: @escaping NavigationReceiveResumeValueOnlyHandler<T>) -> some View {
        self.modifier(OnNavigationReceiveModifier<T>(handler: { (value, _) in handler(value) }))
    }

    /// Handler receives values of a specific type broadcast via `navigator.send`.
    /// ```swift
    /// .onNavigationReceive { (destination: HomeDestinations, navigator) in
    ///     navigator.navigate(to: destination)
    ///     return .auto
    /// }
    /// ```
    /// This version passes in the current navigator in addition to the sent value.
    ///
    /// Receive handlers return a value of type ``NavigationReceiveResumeType``. That tells Navigator how to process the remaining
    /// values in the queue.
    ///
    /// Note that there should be one and only one registered handler for a given type in the navigation tree. If more than
    /// one exists the first handler will consume the value and the remaining handlers should be ignored.
    public func onNavigationReceive<T: Hashable>(handler: @escaping NavigationReceiveResumeHandler<T>) -> some View {
        self.modifier(OnNavigationReceiveModifier<T>(handler: handler))
    }

    /// Handler receives values of a specific type broadcast via `navigator.send`
    /// and assigns the result to a bound value.
    ///
    /// Use this when you want to drive local state from navigation sends
    /// without writing a full receive handler.
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     @State private var selectedTab: RootTabs = .home
    ///
    ///     var body: some View {
    ///         TabView(selection: $selectedTab) {
    ///             // ...
    ///         }
    ///         .onNavigationReceive(assign: $selectedTab)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - binding: The binding to update when a value is received.
    ///   - delay: Optional delay to wait before resuming any remaining values.
    public func onNavigationReceive<T: Hashable & Equatable>(assign binding: Binding<T>, delay: TimeInterval? = nil) -> some View {
        self.modifier(OnNavigationReceiveModifier<T> { (value, _) in
            if binding.wrappedValue == value {
                return .immediately
            }
            binding.wrappedValue = value
            if let delay {
                return .after(delay)
            } else {
                return .auto
            }
        })
    }

    /// Convenience receiver for NavigationDestinations values broadcast via `navigator.send`.
    ///
    /// The following code navigates to a specific destination and returns normally.
    /// ```swift
    /// .onNavigationReceive { (destination: HomeDestinations, navigator) in
    ///     navigator.navigate(to: destination)
    ///     return .auto
    /// }
    /// ```
    /// That sequence occurs so often that there's a shortcut that does the same thing.
    /// ```swift
    /// .navigationAutoReceive(HomeDestinations.self)
    /// ```
    public func navigationAutoReceive<T: NavigationDestination>(_ type: T.Type, delay: TimeInterval? = nil) -> some View {
        self.modifier(OnNavigationReceiveModifier<T> { (value, navigator) in
            navigator.navigate(to: value)
            if let delay {
                return .after(delay)
            } else {
                return .auto
            }
        })
    }

}

public typealias NavigationReceiveResumeHandler<T> = (_ value: T, _ navigator: Navigator) -> NavigationReceiveResumeType
public typealias NavigationReceiveResumeValueOnlyHandler<T> = (_ value: T) -> NavigationReceiveResumeType

public enum NavigationReceiveResumeType {
    /// Automatically resumes sending remaining values after a delay
    case auto

    /// Resumes sending remaining values immediately, without delay
    case immediately

    /// Automatically resumes sending remaining values after a specified delay
    case after(TimeInterval)

    ///  Replaces remaining values with new values after a brief delay
    case replacing([any Hashable])

    ///  Inserts new values into the queue
    case inserting([any Hashable])

    ///  Appends new values onto the queue
    case appending([any Hashable])

    /// Cancels any remaining values in the send queue
    case cancel
}

private struct OnNavigationReceiveModifier<T: Hashable>: ViewModifier {
    internal let handler: NavigationReceiveResumeHandler<T>
    @Environment(\.navigator) var navigator: Navigator
    init(handler: @escaping NavigationReceiveResumeHandler<T>) {
        self.handler = handler
    }
    func body(content: Content) -> some View {
        content
            // A receiver just mounted: deliver sends that arrived before any receiver was
            // subscribed (e.g. a route performed right after opening this window).
            // See CODE_AUDIT_18 §3.17.
            .task {
                navigator.root.replayUndeliveredSends(for: T.self)
            }
            .onReceive(navigator.publisher) { values in
                if let value: T = values.consume() {
                    navigator.log(.send(.receiving(value)))
                    let type = handler(value, navigator)
                    if case .auto = type, let destination = value as? any NavigationDestination {
                        values.resume(destination.receiveResumeType)
                    } else {
                        values.resume(type)
                    }
                }
            }
    }
}

@MainActor
internal final class NavigationSendValues {

    internal let navigator: Navigator
    internal let value: any Hashable
    internal let values: [any Hashable]
    internal let identifier: String?
    /// When a replayed send was first stashed; `nil` for a fresh send.
    internal let firstStashedAt: ContinuousClock.Instant?

    internal var consumed: Bool = false

    internal init(
        navigator: Navigator,
        value: any Hashable,
        values: [any Hashable],
        identifier: String? = nil,
        firstStashedAt: ContinuousClock.Instant? = nil
    ) {
        self.navigator = navigator
        self.value = value
        self.values = values
        self.identifier = identifier
        self.firstStashedAt = firstStashedAt
    }

    // See CODE_AUDIT_15 §3.4.
    isolated deinit {
        if consumed == false {
            navigator.log(.error("missing receive handler for type: \(String(describing: type(of: value)))!!!"))
            if identifier == nil {
                navigator.root.stashUndeliveredSend([value] + values, at: firstStashedAt ?? .now)
            }
        }
    }

    @MainActor
    internal func consume<T>(_ identifier: String? = nil) -> T? {
        if let value = value as? T, self.identifier == identifier {
            if consumed {
                navigator.log(.error("additional receive handlers ignored for type: \(type(of: value))!!!"))
                return nil
            }
            consumed.toggle()
            return value
        }
        return nil
    }

    @MainActor
    internal func resume(_ resume: NavigationReceiveResumeType) {
        navigator.resume(resume, values: values)
    }

}

extension NavigationSendValues {

    convenience init<T: Hashable>(navigator: Navigator, identifier: String, value: T) {
        self.init(navigator: navigator, value: value, values: [], identifier: identifier)
    }

}

extension Navigator {
    @MainActor
    internal func stashUndeliveredSend(_ values: [any Hashable], at stashedAt: ContinuousClock.Instant = .now) {
        pruneUndeliveredSends()
        undeliveredSends.append((values, stashedAt))
        if undeliveredSends.count > Self.maximumUndeliveredSends {
            undeliveredSends.removeFirst(undeliveredSends.count - Self.maximumUndeliveredSends)
        }
    }

    /// Replays only the stashed sends a receiver of `type` can consume; sends for other
    /// receivers stay stashed (and keep their original timestamp) until theirs mounts or they
    /// expire. See CODE_AUDIT_19 §3.2.
    @MainActor
    internal func replayUndeliveredSends<T: Hashable>(for type: T.Type) {
        pruneUndeliveredSends()
        guard !undeliveredSends.isEmpty else { return }
        let isForReceiver: ((values: [any Hashable], at: ContinuousClock.Instant)) -> Bool = { send in
            send.values.first.map { $0 is T } ?? false
        }
        let pending = undeliveredSends.filter(isForReceiver)
        guard !pending.isEmpty else { return }
        undeliveredSends.removeAll(where: isForReceiver)
        for send in pending {
            self.send(values: send.values, firstStashedAt: send.at)
        }
    }

    @MainActor
    private func pruneUndeliveredSends() {
        let now = ContinuousClock.now
        undeliveredSends.removeAll { now - $0.at > Self.undeliveredSendLifetime }
    }
}
