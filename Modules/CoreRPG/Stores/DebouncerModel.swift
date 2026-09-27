// @copyright André Trettin

import Foundation

@MainActor @Observable
public final class DebouncerModel<T: Sendable>: Sendable {
    @ObservationIgnored
    public var input: T {
        didSet { scheduleUpdate() }
    }
    public var output: T

    @ObservationIgnored
    private var debounceTask: Task<Void, Never>?
    @ObservationIgnored
    private let delay: Double

    public init(initialValue: T, delay: Double = 1) {
        input = initialValue
        output = initialValue
        self.delay = delay
    }

    private func scheduleUpdate() {
        debounceTask?.cancel()
        let value = input
        debounceTask = Task { [weak self, delay] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.output = value
        }
    }
}

/// Starts a cancellable, delayed action on the main actor — the
/// sleep-then-check-cancellation-then-act pattern used for the app's short
/// settle/debounce delays (haptics, focus, link recalculation), previously
/// hand-rolled near-identically at 6+ call sites. Callers still own
/// cancelling any previous pending call themselves before starting a new
/// one, same as any other stored `Task`:
/// ```swift
/// myTask?.cancel()
/// myTask = delayedTask(.settleDelay) { doSomething() }
/// ```
/// A free function rather than a `Task` extension: inside `extension Task
/// where Success == Void, Failure == Never`, an unqualified `Task` inside
/// the method body resolves to `Self` — colliding with `sleep(for:)`,
/// which requires `Success == Never` — so this sidesteps that entirely.
/// See CODE_AUDIT §9.4.
@discardableResult
@MainActor
public func delayedTask(_ delay: Duration, operation: @escaping @MainActor () -> Void) -> Task<Void, Never> {
    Task {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        operation()
    }
}

public extension Duration {
    /// The short pause the editors and sheet use to coalesce a burst of edits (typing, drag
    /// moves, reconciles) into one update. See CODE_AUDIT_18 §9.17.
    static let settleDelay: Duration = .milliseconds(100)
}
