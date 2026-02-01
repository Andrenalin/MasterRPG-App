// @copyright André Trettin

import CoreRPG
import SwiftUI

struct IntelligenceUnavailableView: View {
    @Environment(FoundationManager.self) var manager
    var body: some View {
        ContentUnavailableView {
            Label("AI Not available", systemImage: NetworkModules.generator.icon)
        } description: {
            Text(manager.notAvailableReason)
        } actions: {
            Button {
                manager.checkIsAvailable()
            } label: {
                Text("Try again", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    IntelligenceUnavailableView()
        .environment(FoundationManager())
}
