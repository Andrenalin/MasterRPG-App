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
