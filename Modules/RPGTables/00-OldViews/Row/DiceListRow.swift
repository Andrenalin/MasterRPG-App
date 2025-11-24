// @copyright André Trettin

import SwiftUI

struct DiceListRow: View {
    let name: LocalizedStringKey
    let icon: String

    var body: some View {
        Label {
            Text(name, bundle: .module)
                .font(.subheadline)
        } icon: {
            Image(systemName: icon)
                .imageScale(.large)
                .foregroundStyle(Color.accentColor)
        }
    }
}
