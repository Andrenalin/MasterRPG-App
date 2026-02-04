// @copyright André Trettin

import SwiftUI

public struct StretchingHeaderView<Content: View>: View {
    public let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        GeometryReader { geo in
            VStack(content: content)
                .frame(width: geo.size.width, height: height(for: geo))
                .offset(y: offset(for: geo))
        }
    }
}

private extension StretchingHeaderView {
    func height(for proxy: GeometryProxy) -> CGFloat {
        let y = proxy.frame(in: .global).minY
        return proxy.size.height + max(0, y)
    }

    func offset(for proxy: GeometryProxy) -> CGFloat {
        let y = proxy.frame(in: .global).minY
        return min(0, -y)
    }
}

#Preview {
    NavigationStack {
        List {
            Section(header:
                StretchingHeaderView {
                    Image(systemName: "bookmark")
                        .resizable()
                        .scaledToFit()
                }
                .frame(height: 200)
            ) {
                ForEach(0 ..< 20) { i in
                    Text("Row \(i)")
                }
            }
        }
        .listStyle(.automatic)
        #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}
