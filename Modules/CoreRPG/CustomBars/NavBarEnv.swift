// @copyright André Trettin

import SwiftUI

#Preview("Title") {
    NavBarTitleView(title: "Adventure")
}

#Preview("Background") {
    NavBarBackground.linearPinkBlue
        .frame(height: 120)
}

public extension View {
    func navBarTitle() -> some View {
        modifier(NavBarTitleModifier())
    }

    func navBarBlurBackground() -> some View {
        modifier(NavBarBackgroundModifier())
    }
}

public struct NavBarTitleView: View {
    public let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .navBarTitle()
    }
}

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

struct NavBarBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .ignoresSafeArea()
            .overlay(.ultraThinMaterial)
    }
}

struct NavBarTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.largeTitle.bold())
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
