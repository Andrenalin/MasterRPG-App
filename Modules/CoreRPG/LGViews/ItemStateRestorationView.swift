// @copyright André Trettin

import SwiftUI

public struct ItemStateRestorationView<Route: ItemDetailRoute & Equatable, Root: ItemRootControllable>: View {
    public init(root: Root, keyPrefix: String, restoresState: Bool = true) {
        self.root = root
        self.keyPrefix = keyPrefix
        self.restoresState = restoresState
    }

    let root: Root
    private let keyPrefix: String
    private let restoresState: Bool

    @Environment(\.itemStateRestorationEnabled) private var itemStateRestorationEnabled

    @ViewBuilder public var body: some View {
        if restoresState && itemStateRestorationEnabled {
            let _ = Self.printViewChangesOnlyInDebug()

            Color.clear
                .modifier(ItemStateRestorationModifier<Route, Root>(root: root, keyPrefix: keyPrefix))
        } else {
            Color.clear
        }
    }
}

private struct ItemStateRestorationModifier<Route: ItemDetailRoute & Equatable, Root: ItemRootControllable>: ViewModifier {
    init(root: Root, keyPrefix: String) {
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

    func body(content: Content) -> some View {
        content
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
            .task {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

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

enum ItemStateRestorationPreviewRoute: @MainActor ItemDetailRoute {
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
    ItemStateRestorationView<ItemStateRestorationPreviewRoute, ItemRootController>(
        root: .fake,
        keyPrefix: "preview",
        restoresState: false
    )
        .environment(AppWindowSizeModel())
}

private struct ItemStateRestorationEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var itemStateRestorationEnabled: Bool {
        get { self[ItemStateRestorationEnabledKey.self] }
        set { self[ItemStateRestorationEnabledKey.self] = newValue }
    }
}

public extension View {
    func itemStateRestorationEnabled(_ enabled: Bool) -> some View {
        environment(\.itemStateRestorationEnabled, enabled)
    }
}
