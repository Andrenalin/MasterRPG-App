// @copyright André Trettin

import SwiftUI

public extension View {
    @ViewBuilder
    func checkAnimationEnd<Value: VectorArithmetic>(for value: Value, endValue: Value, onEnd: @Sendable @escaping () -> Void) -> some View where Value: Sendable {
        modifier(AnimationEndCallback(for: value, endValue: endValue, onEnd: onEnd))
    }
}

private struct AnimationEndCallback<Value: VectorArithmetic>: Animatable, ViewModifier, Sendable where Value: Sendable {
    var animatableData: Value {
        didSet {
            checkIfFinished()
        }
    }

    var endValue: Value
    var onEnd: @Sendable () -> Void

    init(for value: Value, endValue: Value, onEnd: @Sendable @escaping () -> Void) {
        self.animatableData = value
        self.endValue = endValue
        self.onEnd = onEnd
    }

    func body(content: Content) -> some View {
        content
    }

    private func checkIfFinished() {
        if endValue == animatableData {
            Task { @MainActor in
                onEnd()
            }
        }
    }
}
