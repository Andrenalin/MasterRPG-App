// @copyright André Trettin

import SwiftUI

public struct ItemStateRestorationView<Route: ItemDetailRoute & Equatable, Root: ItemRootControllable>: View {
    public init(root: Root, keyPrefix: String) {
        self.root = root
        _selectedItemId = SceneStorage("\(keyPrefix)SelectedItem")
        _displayMode = SceneStorage(wrappedValue: .medium, "\(keyPrefix)DisplayModel")
        _listMode = SceneStorage(wrappedValue: .list, "\(keyPrefix)ListModel")
    }

    let root: Root

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @SceneStorage private var selectedItemId: String?
    @SceneStorage private var displayMode: ListDisplayModel.DisplayMode
    @SceneStorage private var listMode: ListDisplayModel.ListMode

    @State private var route: Route?

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        Color.clear
            .applyIf(appSizeModel.mode == .compact) {
                $0.navigate(to: $route)
                    .onChange(of: route) {
                        if route == nil && root.navigationModel.selectedItemId != nil {
                            root.navigationModel.selectedItemId = nil
                        }
                    }
            }
            .syncListDisplay(listControllable: root.folderListControllable, displayMode: $displayMode, listMode: $listMode)
            .onChange(of: root.navigationModel.selectedItemId) {
                if let itemId = root.navigationModel.selectedItemId {
                    route <=> Route.detailRoute(itemId: itemId)
                    selectedItemId <=> itemId.uuidString
                    if root.folderListControllable.listModel.selectedItemId != itemId {
                        root.folderListControllable.listModel.set(selectedItemId: itemId)
                    }
                } else {
                    route <=> nil
                    selectedItemId <=> nil
                    if root.folderListControllable.listModel.selected != nil {
                        root.folderListControllable.listModel.update(selection: Set())
                    }
                }
            }
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if let itemIdString = selectedItemId, let itemId = UUID(uuidString: itemIdString) {
                        if root.navigationModel.selectedItemId != itemId {
                            root.navigationModel.selectedItemId = itemId
                        }
                    } else {
                        selectedItemId <=> nil
                        root.navigationModel.selectedItemId <=> nil
                    }
                }
            }
    }
}

private enum ItemStateRestorationPreviewRoute: @MainActor ItemDetailRoute {
    case detail(UUID)

    var id: UUID { detail() ?? UUID() }

    func detail() -> UUID? {
        if case let .detail(id) = self { id } else { nil }
    }

    func reset(detail: UUID) -> Self { .detail(detail) }
    static func detailRoute(itemId: UUID) -> Self { .detail(itemId) }

    var body: some View { EmptyView() }
}

#Preview {
    ItemStateRestorationView<ItemStateRestorationPreviewRoute, ItemRootController>(root: .fake, keyPrefix: "preview")
        .environment(AppWindowSizeModel())
}
