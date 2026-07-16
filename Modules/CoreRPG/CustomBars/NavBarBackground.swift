// @copyright André Trettin

import SwiftUI

public struct NavBarBackground<Content: View>: View {
    public let content: () -> Content

    public init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .navBarBlurBackground()
    }
}

public extension NavBarBackground where Content == LinearGradient {
    static var linearPinkBlue: NavBarBackground {
        linear(colors: [.pink.opacity(0.8), .blue.opacity(0.5)])
    }

    static func linear(colors: [Color]) -> NavBarBackground {
        NavBarBackground {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

public extension NavBarBackground where Content == Color {
    static func colored(_ color: Color) -> NavBarBackground {
        NavBarBackground {
            color
        }
    }
}

#Preview("Background") {
    NavBarBackground {
        LinearGradient(
            colors: [.pink.opacity(0.8), .blue.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
        .frame(height: 120)
}
