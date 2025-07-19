// @copyright André Trettin

import SwiftUI

public protocol GridButtonValue {
    var icon: String { get }
    var title: String { get }
    var color: Color { get }
}

extension NetworkModules: GridButtonValue {}

public struct GridButtonView<Value: GridButtonValue>: View {
    public init(value: Value, color: Color, action: @escaping () -> Void) {
        self.value = value
        self.color = color
        self.action = action
    }

    let value: Value
    let color: Color
    let action: () -> Void

    public var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: value.icon)
                    .resizable()
                    .frame(width: 50, height: 50)
#if os(visionOS)
                    .foregroundStyle(color)
#endif

                Text(value.title).minimumScaleFactor(0.5).lineLimit(1)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .font(.title)
#if os(visionOS)
        .buttonStyle(.borderless)
        .background(.regularMaterial, in: .capsule)
        .background(color.secondary, in: .capsule)
#else
        .rowEditColor(backgroundColor: color)
#endif
        .contentShape(.rect)
    }
}
