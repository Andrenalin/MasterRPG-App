// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct RootGame: View {
    @Environment(WeatherRoot.self) private var root
    
    var body: some View {
        GeometryReader { proxy in
            WeatherViewer(model: root.gameController.currentItem(), size: proxy.size, useGame: true)
        }
        .ignoresSafeArea()
    }
}


struct WeatherWindow: View {
    let selection: ItemSelection
    
    @Environment(\.dismiss) private var dismiss
    @Environment(WeatherRoot.self) private var root
    
    var body: some View {
        GeometryReader { proxy in
            WeatherViewer(model: root.itemController.itemOrEmpty(for: selection.itemId), size: proxy.size, useGame: true)
        }
        .ignoresSafeArea()
#if os(iOS)
        .statusBar(hidden: true)
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation { dismiss() }
            } label: {
                Image(systemName: "xmark")
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .foregroundStyle(Color.accentColor)
            .clipShape(.circle)
            .padding()
        }
#endif
    }
}
