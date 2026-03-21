// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct DetailListView: View {
    init(root: WeatherRootModel, model: WeatherModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: WeatherRootModel
    let model: WeatherModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var animate: Bool = false
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.weather.viewerWindowId, canShow: true, route: { DetailRoute.viewer($0) })
    @State private var photoSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: true, allowCollections: false, allowEntrySelection: false)
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: WeatherDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: false) {
        } editor: {
            WeatherEditor(model: model)
        } inspector: {
            root.photoRoot.viewController.linkListView(type: .inspector, itemSelectionModel: photoSelectionModel)
        } overlay: {
            OverlayViewer(model: model, animate: $animate)
                .allowsHitTesting(false)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: openFileWindowModel.itemId, configuration: ViewerConfiguration(closeButton: true)) {
                    openFileWindowModel.showItem = false
                }
            }
        }
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
