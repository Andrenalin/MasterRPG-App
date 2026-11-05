// @copyright André Trettin

import CoreRPG
import SwiftUI

/// A weather of the running game as the picture of a popover on the game map: the full game
/// viewer, animated, filling the space it is given.
struct WeatherPopoverViewer: View {
    let model: WeatherModel

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var isAnimating = false

    var body: some View {
        WeatherViewerContainer(model: model, useGame: true, isAnimating: $isAnimating) {
            $0.id(model.id)
        }
        .clipped()
        .onAppear {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                isAnimating = true
            }
        }
    }
}

#Preview(traits: .mockData) {
    WeatherPopoverViewer(model: .default)
        .frame(width: 280, height: 280)
}
