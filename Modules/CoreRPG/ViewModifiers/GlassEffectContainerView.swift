// @copyright André Trettin

import SwiftUI

public struct GlassEffectContainerView<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder var content: Content

    public var body: some View {
#if os(visionOS)
        content
#else
        GlassEffectContainer {
            content
        }
#endif
    }
}

/// A type alias for GlassEffectContainerView that automatically handles visionOS platform differences.
/// Use this instead of wrapping GlassEffectContainer in #if !os(visionOS) checks.
public typealias GlassEffectContainerAll = GlassEffectContainerView

#Preview {
    GlassEffectContainerView {
        Text(verbatim: "Glass content")
            .padding()
    }
}
