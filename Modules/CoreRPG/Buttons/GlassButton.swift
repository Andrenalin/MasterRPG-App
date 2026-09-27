// @copyright André Trettin

import SwiftUI

#Preview("Regular") {
    GlassButton(action: {}) {
        Label {
            Text(verbatim: "Continue")
        } icon: {
            Image(systemName: "arrow.right")
        }
    }
}

#Preview("Prominent") {
    GlassButton(isProminent: true, action: {}) {
        Label {
            Text(verbatim: "Continue")
        } icon: {
            Image(systemName: "arrow.right")
        }
    }
}

public struct GlassButton<Content: View>: View {
    public init(isProminent: Bool = false,  action: @escaping () -> Void, @ViewBuilder label: () -> Content) {
        self.isProminent = isProminent
        self.label = label()
        self.action = action
    }
    
    let isProminent: Bool
    let label: Content
    let action: () -> Void
    
    public var body: some View {
        if isProminent {
            GlassButtonInnerButtonView(label: label, action: action)
#if !os(visionOS)
                .buttonStyle(.glassProminent)
#endif
        } else {
            GlassButtonInnerButtonView(label: label, action: action)
#if !os(visionOS)
                .buttonStyle(.glass)
#endif
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct GlassButtonInnerButtonView<Content: View>: View {
    let label: Content
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            label
        }
    }
}
