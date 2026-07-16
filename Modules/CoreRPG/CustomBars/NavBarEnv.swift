// @copyright André Trettin

import SwiftUI

#Preview("Title") {
    NavBarTitleView(title: "Adventure")
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
