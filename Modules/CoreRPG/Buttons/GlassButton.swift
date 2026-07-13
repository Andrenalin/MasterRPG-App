// @copyright André Trettin

import SwiftUI

#Preview("Regular") {
    GlassButton(action: {}) {
        Label("Continue", systemImage: "arrow.right")
    }
}

#Preview("Prominent") {
    GlassButton(isProminent: true, action: {}) {
        Label("Continue", systemImage: "arrow.right")
    }
}

public struct GlassButton<Content: View>: View {
    public init(isProminent: Bool = false,  action: @escaping () -> Void, @ViewBuilder label: () -> Content) {
        self.isProminet = isProminent
        self.label = label()
        self.action = action
    }
    
    let isProminet: Bool
    let label: Content
    let action: () -> Void
    
    public var body: some View {
        if isProminet {
            button
#if !os(visionOS)
                .buttonStyle(.glassProminent)
#endif
        } else {
            button
#if !os(visionOS)
                .buttonStyle(.glass)
#endif
        }
    }
    
    private var button: some View {
        Button {
            action()
        } label: {
            label
        }
    }
}
