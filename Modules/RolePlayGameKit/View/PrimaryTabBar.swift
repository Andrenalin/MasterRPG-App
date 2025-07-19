// @copyright André Trettin

#if os(visionOS)
import AndrenalinKit
import SwiftUI

struct PrimaryTabBar: View {
    @Binding var selectedTab: RootRoute

    @Namespace private var hoverEffectNameSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(RootRoute.allTabs) { tab in
                SecondaryTabBarButton(selectedTab: $selectedTab, tab: tab, hoverGroup: HoverEffectGroup(hoverEffectNameSpace))
            }
        }
        .padding(12)
        .fixedSize()
        .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
        .hoverEffect(in: HoverEffectGroup(hoverEffectNameSpace)) { effect, isActive, proxy in
            effect.animation(.default.delay(isActive ? 0.8 : 0.2)) {
                $0.clipShape(
                    .rect(cornerRadius: 28, style: .continuous).size(width: isActive ? proxy.size.width : 64, height: proxy.size.height, anchor: .leading)
                )
            }
        }
    }
}

struct SecondaryTabBarButton: View {
    @Binding var selectedTab: RootRoute
    let tab: RootRoute
    let hoverGroup: HoverEffectGroup?
    
    var body: some View {
        Button {
            withAnimation {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 12) {
                menuIconView(for: tab.icon)
                menuDetailView(for: tab.title)
                    .hoverEffect(FadeEffect(), in: hoverGroup)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BarButtonWithHoverEffectStyle(isSelected: selectedTab == tab, hoverGroup: hoverGroup))
        .hoverEffect(.lift, isEnabled: selectedTab == tab)

    }
    
    func menuIconView(for icon: String) -> some View {
        Image(systemName: icon)
    }

    func menuDetailView(for title: String) -> some View {
        Text(title)
    }
}

struct BarButtonWithHoverEffectStyle: ButtonStyle {
    let isSelected: Bool
    let hoverGroup: HoverEffectGroup?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var hoverEffectNamespace

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.thinMaterial)
                        .hoverEffect(reduceMotion ? HoverEffect(FadeEffect()) : HoverEffect(.empty), in: hoverGroup)
                        .hoverEffect(.highlight)

                    if reduceMotion {
                        Circle()
                            .fill(.thinMaterial)
                            .hoverEffect(.highlight)
                            .hoverEffect(FadeEffect(from: 1, to: 0), in: hoverGroup)
                    }
                }
                .hoverEffect(in: HoverEffectGroup(hoverEffectNamespace)) { effect, isActive, proxy in
                    effect.opacity(isActive ? 1 : (isSelected ? 1 : 0.0))
                }
            }
            .hoverEffect()
            .hoverEffect(.highlight)
            .hoverEffect(reduceMotion ? HoverEffect(.empty) : HoverEffect(ExpandEffect()), in: hoverGroup)
    }
}

struct ExpandEffect: CustomHoverEffect {
    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, proxy in
            effect.animation(.default.delay(isActive ? 0.8 : 0.2)) {
                $0.clipShape(.rect(cornerRadius: 28, style: .continuous).size(
                    width: isActive ? proxy.size.width : proxy.size.height,
                    height: proxy.size.height, anchor: .leading)
                )
                .scaleEffect(isActive ? 1.05 : 1.0)
            }
        }
    }
}

struct FadeEffect: CustomHoverEffect {
    var from: Double = 0
    var to: Double = 1

    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, _ in
            effect.animation(.default.delay(isActive ? 0.8 : 0.2)) {
                $0.opacity(isActive ? to : from)
            }
        }
    }
}

#Preview {
    @Previewable @State var otherSplitTab: RootRoute = .game
    @Previewable @State var tabId = UUID()

    TabView {
        Tab("Adventure", systemImage: "photo") {
            VStack(alignment: .leading) {
                PrimaryTabBar(selectedTab: $otherSplitTab)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Tab("Setting", systemImage: "gear") {
            Text("Nothing")
        }
    }
}
#endif
