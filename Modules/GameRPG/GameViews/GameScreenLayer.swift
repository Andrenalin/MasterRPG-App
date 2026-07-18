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
        ManagedNavigationStack {
            ZStack(alignment: .topLeading) {
                surface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                chrome
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
