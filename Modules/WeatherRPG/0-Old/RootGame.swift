// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RootGame: View {
    @Environment(WeatherRootModel.self) private var root
    
    var body: some View {
        GeometryReader { proxy in
            WeatherViewer(model: root.gameController.currentItem(), size: proxy.size, useGame: true, isAnimating: .constant(false))
        }
        .ignoresSafeArea()
    }
}
