// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: WeatherRootModel
    let model: WeatherModel
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.weather.viewerWindowId, canShow: true, route: { DetailRoute.viewer($0) })
    @Environment(\.navigator) private var navigator
    
    @State private var animate: Bool = false
    
    var body: some View {
        DetailFolderListView(root: root, model: model, animate: $animate)
            .toolbar {
                toolbarContent
            }
            .environment(openFileWindowModel)
            .environment(root.folderListController.cacheListItemModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
            }
    }
    
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .secondaryActionAll) {
            if !model.specialCategory {
                animateButton
            }
        }
    }
    
    var animateButton: some View {
        ControlGroup {
            Button {
                withAnimation { animate.toggle() }
            } label: {
                Label {
                    Text("Animate", bundle: .module)
                } icon: {
                    Image(systemName: "film\(animate ? ".fill" : "")")
                }
            }
            .contentTransition(.symbolEffect(.replace.wholeSymbol))
        }
    }
}
