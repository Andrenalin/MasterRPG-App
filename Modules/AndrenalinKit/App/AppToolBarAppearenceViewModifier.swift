// @copyright André Trettin

import SwiftUI

public extension View {
    func appToolBarAppearence(color: Color = .blue) -> some View {
        modifier(AppToolBarAppearenceViewModifier(color: color))
    }
}

struct AppToolBarAppearenceViewModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .onAppear {
                    let appearance = UITabBarAppearance()
                    appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
                    appearance.backgroundColor = UIColor(color.opacity(0.2))
                    UITabBar.appearance().standardAppearance = appearance
                    UITabBar.appearance().scrollEdgeAppearance = appearance

                    UITextField.appearance().clearButtonMode = .whileEditing
                }
        #else
            content
        #endif
    }
}
