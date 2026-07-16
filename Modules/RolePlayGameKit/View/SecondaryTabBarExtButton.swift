// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SwiftUI

struct SecondaryTabBarExtButton: View {
    let tab: ExtendedTabRoute
    let hoverGroup: HoverEffectGroup?

    @Environment(AppModel.self) var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                appModel.selectedExtendedModule = tab
            }
        } label: {
            HStack(spacing: 12) {
                menuIconView(for: tab.icon)
                menuDetailView(for: tab.title)
                    .hoverEffect(FadeEffect(), in: hoverGroup)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BarButtonWithHoverEffectStyle(isSelected: appModel.selectedExtendedModule == tab, hoverGroup: hoverGroup))
        .hoverEffect(.lift, isEnabled: appModel.selectedExtendedModule == tab)
    }

    func menuIconView(for icon: String) -> some View {
        Image(systemName: icon)
    }

    func menuDetailView(for title: String) -> some View {
        Text(verbatim: title)
    }
}

private struct FadeEffect: CustomHoverEffect {
    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, _ in
            effect.opacity(isActive ? 1 : 0)
        }
    }
}

#Preview("Secondary tab button") {
    SecondaryTabBarExtButton(tab: .maps, hoverGroup: nil)
        .environment(AppModel())
        .padding()
}
#endif
