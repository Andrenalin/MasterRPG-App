// @copyright André Trettin

import SwiftUI

extension View {
    public func itemSplitViewSizeMode(_ sizeMode: WideMode) -> some View {
        environment(\.itemSplitViewSizeMode, sizeMode)
    }
}

public struct SplitItemList<List: View, Detail: View>: View {
    public init(listController: any ListControllable, editController: any EditControllable, emptyTitle: LocalizedStringKey, bundle: Bundle?, @ViewBuilder listView: @escaping () -> List, @ViewBuilder detail: @escaping (ItemRowTreeModel) -> Detail) {
        self.listController = listController
        self.editController = editController
        self.emptyTitle = emptyTitle
        self.bundle = bundle
        self.listView = listView
        self.detailView = detail
    }

    let listController: any ListControllable
    let editController: any EditControllable
    let emptyTitle: LocalizedStringKey
    let bundle: Bundle?
    let listView: () -> List
    let detailView: (ItemRowTreeModel) -> Detail

    @Environment(\.itemSplitViewSizeMode) private var itemSplitSizeMode
    @Environment(\.itemListChildrenConfiguration) private var childrenConfiguration

    @State private var column: NavigationSplitViewVisibility = .all
    @State private var path: [SelectedRoute] = []

    private var sizeMode: WideMode {
#if os(tvOS)
        .small
#else
        itemSplitSizeMode
#endif
    }

    public var body: some View {
        let _ = Self._printChanges()
        let _ = print("SplitItemList: \(listController.model.listTitleName)")
        
        @Bindable var itemListModel = listController.model
        
        Group {
            if sizeMode == .small {
                NavigationStack(path: $path) {
                    listInternalView
                        .frame(minWidth: 250, maxWidth: .infinity)
                        .onChange(of: itemListModel.selectedItem, initial: true) {
                            guard itemListModel.allowEditing || childrenConfiguration.canNavigate || childrenConfiguration.disableSelection else { return }
                            if let item = itemListModel.selectedItem {
                                path = [SelectedRoute(id: item.id)]
                            } else {
                                path = []
                                itemListModel.selectedItem = nil
                            }
                        }
                        .onChange(of: path, initial: false) {
                            if path.isEmpty {
                                listController.resetSelectedItem()
                            }
                        }
                        .navigationDestination(for: SelectedRoute.self) { item in
                            SplitItemDetail(editController: editController, listController: listController, emptyTitle: emptyTitle, bundle: bundle, detailView: detailView)
                        }
                }
            } else {
                NavigationSplitView(columnVisibility: $column) {
                    listInternalView
                        .frame(minWidth: 250)
                } detail: {
                    SplitItemDetail(editController: editController, listController: listController, emptyTitle: emptyTitle, bundle: bundle, detailView: detailView)
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
    }

    @ViewBuilder
    var listInternalView: some View {
        listView()
    }
}

struct SplitItemDetail<Detail: View>: View {
    let editController: any EditControllable
    let listController: any ListControllable
    let emptyTitle: LocalizedStringKey
    let bundle: Bundle?
    let detailView: (ItemRowTreeModel) -> Detail

    var body: some View {
//        let _ = Self._printChanges()
//        let _ = print("SplitItemDetail: \(Unmanaged.passUnretained(listController.model).toOpaque())")
//        let _ = print("SplitItemDetail: \(listController.model.listTitleName) -> S: \(listController.model.selectedItem?.model.itemId) == V: \(editController.model.id)")

        Group {
            if let selectedItem = listController.model.selectedItem {
                detailView(selectedItem)
            } else {
                ContentUnavailableView {
                    Label { Text(emptyTitle, bundle: bundle) } icon: { Image(systemName: editController.itemControllable.itemDataModel.networkModule.icon) }
                } description: {
                    Text("Choose an item to see more details", bundle: .module)
                }
            }
        }
        .animation(.default, value: listController.model.selectedItem)
    }
}

extension EnvironmentValues {
#if os(tvOS)
    @Entry public var itemSplitViewSizeMode: WideMode = .small
#else
    @Entry public var itemSplitViewSizeMode: WideMode = .wide
#endif

}

struct SelectedRoute: Identifiable, Equatable, Hashable, Codable {
    var id: UUID
}
