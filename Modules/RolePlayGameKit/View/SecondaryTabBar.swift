// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SwiftUI

struct SecondaryTabBar: View {
    @Namespace private var hoverEffectNameSpace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ExtendedTabRoute.limitedTabs) { tab in
                SecondaryTabBarExtButton(tab: tab, hoverGroup: HoverEffectGroup(hoverEffectNameSpace))
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

struct SecondaryTabBarExtButton: View {
    let tab: ExtendedTabRoute
    let hoverGroup: HoverEffectGroup?

    @Environment(AppModel.self) var appModel
    
    var body: some View {
        Button {
            withAnimation {
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
        Text(title)
    }
}

#Preview {
    @Previewable @State var otherSplitTab: RootRoute = .game
    @Previewable @State var tabId = UUID()

    TabView {
        Tab("Adventure", systemImage: "photo") {
            VStack(alignment: .leading) {
                SecondaryTabBar()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Tab("Setting", systemImage: "gear") {
            Text("Nothing")
        }
    }
}

#Preview("Secondary tab button") {
    SecondaryTabBarExtButton(tab: .maps, hoverGroup: nil)
        .environment(AppModel())
        .padding()
}
#endif
