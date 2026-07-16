// @copyright André Trettin

import SwiftUI

public struct QuickEditorButtonView<Value: Numeric>: View {
    public init(number: Binding<Value>, value: Value, title: String, isAddition: Bool) {
        _number = number
        self.value = value
        self.title = title
        self.isAddition = isAddition
    }
    
    @Binding public var number: Value
    public let value: Value
    public let title: String
    public let isAddition: Bool
    
    public var body: some View {
        Button {
            withAnimation {
                if isAddition {
                    number += value
                } else {
                    number -= value
                }
            }
        } label: {
            Text(verbatim: "\(isAddition ? "+" : "-")\(title)")
        }
#if os(iOS)
        .fixedSize()
        .buttonStyle(.quickAdd)
#elseif os(visionOS)
        .fixedSize()
        .borderLessTVBottonStyle()
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
            .background(.ultraThinMaterial)
            .shadow(radius: 10)
            .clipShape(Circle())
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0 : 0.2), radius: 10, x: 10, y: 10)
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
