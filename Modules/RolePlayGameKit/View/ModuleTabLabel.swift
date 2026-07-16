// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ModuleTabLabel: View {
    let title: String
    let icon: String
    let color: Color

    init(route: RootRoute, color: Color? = nil) {
        title = route.title
        icon = route.icon
        self.color = color ?? route.module.tint
    }

    var body: some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
        }
    }
}

#Preview("Game module tab") {
    ModuleTabLabel(route: .game)
        .padding()
}
