// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Owns the full-window game surface and its chrome as independent siblings.
/// Neither sidebar transitions nor toolbar content can change the proposal
/// received by the map or RealityView.
struct GameScreenLayer<Surface: View, Chrome: View>: View {
    let surface: Surface
    let chrome: Chrome

    init(
        @ViewBuilder surface: () -> Surface,
        @ViewBuilder chrome: () -> Chrome
    ) {
        self.surface = surface()
        self.chrome = chrome()
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        VStack {
            // The clear window-sized view is the only layout participant.
            // Both overlays receive the window proposal, but neither the map's
            // logical size nor a RealityView's ideal size can resize the chrome.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    surface
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }
                .overlay(alignment: .topLeading) {
                    chrome
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        }
    }
}

#Preview("Game screen layer") {
    GameScreenLayer {
        LinearGradient(
            colors: [.blue, .teal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    } chrome: {
        VStack {
            Label("Game controls", systemImage: "gamecontroller.fill")
                .padding()
                .background(.regularMaterial, in: .capsule)
            Spacer()
        }
        .padding()
    }
    .frame(width: 640, height: 480)
}
