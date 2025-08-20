// @copyright André Trettin

import SwiftUI

extension View {
    func tabBarPlacementModifier(listControllable: any ListControllable) -> some View {
        modifier(TabBarPlacementViewModifier(listControllable: listControllable))
    }
}

struct TabBarPlacementViewModifier: ViewModifier {
    let listControllable: any ListControllable

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @Environment(TabTitleModel.self) private var tabTitleModel
#endif

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .onChange(of: tabBarPlacement, initial: true) {
                tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
            }
            .onChange(of: horizontalSizeClass, initial: true) {
                listControllable.listDisplayModel.isPadStyle = horizontalSizeClass != .compact
                tabTitleModel.toggleTitles(horizontalSizeClass: horizontalSizeClass, tabBarPlacement: tabBarPlacement)
            }
#else
        content
#endif
    }
}
