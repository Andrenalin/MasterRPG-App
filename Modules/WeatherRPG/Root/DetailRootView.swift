// @copyright André Trettin

import CoreRPG

import SwiftUI
import PhotoRPG

struct DetailRootView: View {
    let root: WeatherRootModel
    let model: WeatherModel

    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

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
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.weather.viewerWindowId, canShow: true, route: { DetailRoute.viewer($0) })
    @State private var animate: Bool = false
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: WeatherDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedId: model.id, editorAsBackground: false) {
        } editor: {
            WeatherEditor(model: model)
        } inspector: {
            root.photoRoot.viewController.linkWindow(isInspector: true)
        } overlay: {
            OverlayViewer(animate: $animate)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
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
        .tint(root.module.tint)
        .accentColor(root.module.tint)
    }
    
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .secondaryActionAll) {
            animateButton
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
            
            Divider()
        }
    }
}


struct OverlayViewer: View {
    @Binding var animate: Bool

    @Environment(WeatherRootModel.self) private var root
        
    var body: some View {
        GeometryReader { geometry in
            WeatherViewer(model: root.editController.model, size: geometry.size, useGame: false, isAnimating: $animate)
#if !os(visionOS)
                .glassEffect(.clear)
#endif
                .clipShape(.capsule)
        }
        .padding(.horizontal, 16)
        .frame(height: 128)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? WeatherModel.previewId
                root.editController.model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? WeatherModel.previewId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .space)
            }
    } else {
        ManagedNavigationStack {
            DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? WeatherModel.previewId))
                .preferredColorScheme(.dark)
        }
    }
}
