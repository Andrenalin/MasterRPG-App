// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SwiftUI

struct SecondaryTabBar: View {
    @Namespace private var hoverEffectNameSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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
            effect.animation(reduceMotion ? nil : .default.delay(isActive ? 0.8 : 0.2)) {
                $0.clipShape(
                    .rect(cornerRadius: 28, style: .continuous).size(width: isActive ? proxy.size.width : 64, height: proxy.size.height, anchor: .leading)
                )
            }
        }
    }
}

#Preview("Secondary tab bar") {
    TabView {
        Tab {
            VStack(alignment: .leading) {
                SecondaryTabBar()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label {
                Text(verbatim: "Adventure")
            } icon: {
                Image(systemName: "photo")
            }
        }
        Tab {
            Text(verbatim: "Nothing")
        } label: {
            Label {
                Text(verbatim: "Setting")
            } icon: {
                Image(systemName: "gear")
            }
        }
    }
    .environment(AppModel())
}
#endif
