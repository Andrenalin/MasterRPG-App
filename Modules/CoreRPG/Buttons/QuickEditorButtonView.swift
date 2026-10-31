// @copyright André Trettin

import SwiftUI

public struct QuickEditorButtonView<Value: Numeric & Comparable>: View {
    public init(number: Binding<Value>, value: Value, title: String, isAddition: Bool) {
        _number = number
        self.value = value
        self.title = title
        self.isAddition = isAddition
    }
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding public var number: Value
    public let value: Value
    public let title: String
    public let isAddition: Bool
    
    /// The number after one step. Both operands are held to `SheetNumberLimit` first, so a number
    /// typed near `Int.max` cannot overflow the addition. See CODE_AUDIT_22 §5.6.
    private func stepped() -> Value {
        guard let limit = Value(exactly: SheetNumberLimit.maximumMagnitude) else {
            return isAddition ? number + value : number - value
        }
        func bounded(_ candidate: Value) -> Value {
            min(max(candidate, 0 - limit), limit)
        }
        let current = bounded(number)
        let step = bounded(value)
        return bounded(isAddition ? current + step : current - step)
    }

    public var body: some View {
        Button {
            withAnimation(.default.reduced(if: reduceMotion)) {
                number = stepped()
            }
        } label: {
            Text(verbatim: "\(isAddition ? "+" : "-")\(title)")
        }
#if os(iOS)
        .fixedSize()
        .buttonStyle(.quickAdd)
#elseif os(visionOS)
        .fixedSize()
        .borderLessTVButtonStyle()
#endif
        .contentShape(Rectangle())
    }
}

public extension ButtonStyle where Self == QuickAddButtonStyle {
    static var quickAdd: QuickAddButtonStyle {
        QuickAddButtonStyle()
    }
}

public struct QuickAddButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding()
            .foregroundStyle(.teal)
            // `.glassEffectAll(_:in:)` doesn't exist on visionOS (see `PlatformModifiers.swift`);
            // this style is only ever applied on iOS (`.quickAdd` in `QuickEditorButtonView.body`
            // above is iOS-only), but the type still needs to compile for every platform. The
            // previous manual `.background(.ultraThinMaterial)` + `.shadow` + `.clipShape` chain
            // had a dead pre-clip shadow (clipped away before it could render) — `.glassEffectAll`
            // composits shape/shadow internally, so no manual shadow is needed here. See CODE_AUDIT_9 §8.4/§8.5.
#if os(visionOS)
            .background(.ultraThinMaterial)
            .clipShape(.circle)
#else
            .glassEffectAll(.regular, in: .circle)
#endif
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}

#Preview {
    @Previewable @State var number1: Int = 1
    @Previewable @State var number2: Int = 2
    @Previewable @State var number5: Int = 5
    @Previewable @State var number10: Int = 10

    VStack(spacing: 25) {
        QuickEditorButtonView(number: $number1, value: 1, title: "1", isAddition: true)
        QuickEditorButtonView(number: $number2, value: 2, title: "2", isAddition: true)
        QuickEditorButtonView(number: $number5, value: 5, title: "5", isAddition: true)
        QuickEditorButtonView(number: $number10, value: 10, title: "10", isAddition: false)
    }
    .padding()
}
