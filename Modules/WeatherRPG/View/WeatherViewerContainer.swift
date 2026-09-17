// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Measures its own size and hosts a `WeatherViewer` sized to fill it, collapsing
/// the "Color.clear.overlay { WeatherViewer }.onGeometryChange" pattern that was
/// duplicated across `ViewerRootView`, `InlineRowViewer`, and `OverlayViewer`.
/// See CODE_AUDIT_Weather §9.4.
struct WeatherViewerContainer<Overlay: View>: View {
    let model: WeatherModel
    let useGame: Bool
    @Binding var isAnimating: Bool
    let overlay: (WeatherViewer) -> Overlay

    init(
        model: WeatherModel,
        useGame: Bool,
        isAnimating: Binding<Bool>,
        @ViewBuilder overlay: @escaping (WeatherViewer) -> Overlay
    ) {
        self.model = model
        self.useGame = useGame
        _isAnimating = isAnimating
        self.overlay = overlay
    }

    @State private var containerSize: CGSize = .zero

    var body: some View {
        Color.clear
            .overlay {
                overlay(WeatherViewer(model: model, size: containerSize, useGame: useGame, isAnimating: $isAnimating))
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newValue in
                containerSize = newValue
            }
    }
}

extension WeatherViewerContainer where Overlay == WeatherViewer {
    init(model: WeatherModel, useGame: Bool, isAnimating: Binding<Bool>) {
        self.init(model: model, useGame: useGame, isAnimating: isAnimating) { $0 }
    }
}
