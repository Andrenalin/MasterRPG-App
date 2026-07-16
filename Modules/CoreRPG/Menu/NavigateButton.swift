// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct NavigateButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            routeActions.routePage(root.configurable.module, nil, nil)
        } label: {
            Label { Text("Show \(root.configurable.module.title)", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut(key, modifiers: [.command])
    }
}

#Preview {
    NavigateButton(root: ItemRootController.fake, routeActions: RouteActions { _, _, _ in }, key: "n")
}
#endif
