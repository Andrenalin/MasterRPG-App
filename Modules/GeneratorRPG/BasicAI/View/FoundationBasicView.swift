// @copyright André Trettin

import SwiftUI

struct FoundationBasicView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    
    @State private var manager = FoundationManager()
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        Group {
            if manager.isModelAvailable {
                VStack {
                    content()
                }
            } else {
                IntelligenceUnavailableView()
            }
        }
        .environment(manager)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                manager.checkIsAvailable()
            }
        }
    }
}

#Preview {
    FoundationBasicView {
        Text("Test")
    }
    .environment(\.locale, Locale(identifier: "de"))
}
