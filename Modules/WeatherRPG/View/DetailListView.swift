// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    DetailListView(
        root: root,
        model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]),
        folderListController: root.folderListController
    )
}

struct DetailListView: View {
    let root: WeatherRootModel
    let model: WeatherModel
    let folderListController: any FolderListControllable

    @State private var animate: Bool = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailFolderListView(root: root, model: model, folderListController: folderListController, animate: $animate)
            .toolbar {
                toolbarContent
            }
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
#if !os(tvOS)
                root.addSiriContext(to: activity, itemId: model.id)
#endif
            }
#if !os(tvOS)
            .task(id: model.id) {
                await root.donateSiriViewingIntent(for: model.id)
            }
#endif
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
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    animate.toggle()
                }
            } label: {
                Label {
                    Text("Animate", bundle: .module)
                } icon: {
                    Image(systemName: "film\(animate ? ".fill" : "")")
                }
            }
            .accessibilityValue(
                animate ? Text("On", bundle: .module) : Text("Off", bundle: .module)
            )
            .contentTransition(.symbolEffect(.replace.wholeSymbol))
        }
    }
}
