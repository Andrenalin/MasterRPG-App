// @copyright André Trettin

import CoreRPG
import SwiftUI

struct OverlayViewer: View {
    let model: WeatherModel
    @Binding var animate: Bool
    
    @Environment(WeatherRootModel.self) private var root
        
    var body: some View {
        GeometryReader { geometry in
            WeatherViewer(model: model, size: geometry.size, useGame: false, isAnimating: $animate)
#if !os(visionOS)
                .glassEffect(.clear)
#endif
                .clipShape(.capsule)
        }
        .padding(.horizontal, 16)
        .frame(height: 128)
    }
}
