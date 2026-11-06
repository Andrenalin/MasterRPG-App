// @copyright André Trettin

import SwiftUI

public struct QuickEditorButtonView<Value: Numeric & Comparable>: View {
    /// - Parameter isThemed: Draws the button with the app theme's panel and foreground colors on
    ///   every platform (see `ThemedQuickStepButtonStyle`), for editors on a themed panel.
    public init(number: Binding<Value>, value: Value, title: String, isAddition: Bool, isThemed: Bool = false) {
        _number = number
        self.value = value
        self.title = title
        self.isAddition = isAddition
        self.isThemed = isThemed
    }

    private let isThemed: Bool
    
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
        .modifier(QuickEditorButtonStyleModifier(isThemed: isThemed))
        .contentShape(.rect)
    }
}

private struct QuickEditorButtonStyleModifier: ViewModifier {
    let isThemed: Bool

    func body(content: Content) -> some View {
        if isThemed {
            content.buttonStyle(ThemedQuickStepButtonStyle())
        } else {
#if os(iOS)
            content
                .fixedSize()
                .buttonStyle(.quickAdd)
#elseif os(visionOS)
            content
                .fixedSize()
                .borderLessTVButtonStyle()
#else
            content
#endif
        }
    }
}

/// A capsule step button in the app theme: foreground text on a tinted panel fill, inverted
/// (panel text on a foreground fill) while focused or pressed, so the label keeps the contrast
/// the theme guarantees between its panel and foreground on every platform and appearance.
public struct ThemedQuickStepButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StepLabel(configuration: configuration)
    }

    private struct StepLabel: View {
        let configuration: Configuration

        @Environment(\.appTheme) private var theme
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            let isHighlighted = isFocused || configuration.isPressed
            configuration.label
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isHighlighted ? theme.panelColor : theme.foregroundColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isHighlighted ? theme.foregroundColor : theme.controlFillColor, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(theme.controlBorderColor, lineWidth: 1)
                }
        }
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
