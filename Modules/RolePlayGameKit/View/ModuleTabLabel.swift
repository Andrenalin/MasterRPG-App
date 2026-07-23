// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ModuleTabLabel: View {
    let route: RootRoute
    let color: Color?

    @Environment(\.appTheme) private var theme

    init(route: RootRoute, color: Color? = nil) {
        self.route = route
        self.color = color
    }

    var body: some View {
        Label {
            Text(verbatim: route.title)
        } icon: {
            Image(systemName: route.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color ?? theme.tint(for: route.module))
        }
    }
}

#Preview("Game module tab") {
    ModuleTabLabel(route: .game)
        .padding()
}
