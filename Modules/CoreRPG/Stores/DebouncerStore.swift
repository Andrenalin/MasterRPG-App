// @copyright André Trettin

import Combine
import Foundation

public final class DebouncerStore<T>: ObservableObject {
    @Published public var input: T
    @Published public var output: T

    private var debounce: AnyCancellable?

    public init(initialValue: T, delay: Double = 1) {
        input = initialValue
        output = initialValue

        debounce = $input
            .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.output = $0
            }
    }
}

@MainActor @Observable
public final class DebouncerModel<T: Sendable>: Sendable {
    @ObservationIgnored
    @Published public var input: T
    public var output: T

    @ObservationIgnored
    private var debounce: AnyCancellable?

    public init(initialValue: T, delay: Double = 1) {
        input = initialValue
        output = initialValue

        debounce = $input
            .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.output = $0
            }
    }
}
