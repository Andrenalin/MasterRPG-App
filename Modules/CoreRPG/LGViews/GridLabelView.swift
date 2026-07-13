// @copyright André Trettin

import SwiftUI

#Preview {
    GridLabelView(value: NetworkModules.adventure, color: .orange)
        .padding()
}

public protocol GridButtonValue {
    var icon: String { get }
    var title: String { get }
    var color: Color { get }
}

extension NetworkModules: GridButtonValue {}

public struct GridLabelView<Value: GridButtonValue>: View {
    public init(value: Value, color: Color) {
        self.value = value
        self.color = color
    }

    let value: Value
    let color: Color

    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
        Group {
            VStack {
                Image(systemName: value.icon)
                    .resizable()
                    .frame(width: 50, height: 50)
#if os(visionOS)
                    .foregroundStyle(color)
#else
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
#endif

                Text(value.title).minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
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
