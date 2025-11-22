// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct WeatherDetailViewer: View {
    let item: ItemRowTreeModel
    
    @Environment(WeatherRootModel.self) private var root
    @Environment(\.routeActions) private var routeActions

    var body: some View {
        GeometryReader { proxy in
            WeatherViewer(model: model,  size: proxy.size, useGame: true, isAnimating: .constant(false))
        }
        .ignoresSafeArea()
        .environment(\.showGame, true)
        .overlay(alignment: .topTrailing) {
            Button {
                routeActions.routePage(root.itemController.itemDataModel.networkModule, item.model.itemId, item.model.entryId)
            } label: {
                Image(systemName: root.itemController.itemDataModel.networkModule.icon)
            }
            .padding()
        }
    }
    
    var model: WeatherModel {
        root.itemController.itemOrEmpty(for: item.model.itemId)
    }
}
