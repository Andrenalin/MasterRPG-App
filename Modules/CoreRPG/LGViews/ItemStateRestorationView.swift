// @copyright André Trettin

import SwiftUI

/// Gives the list/navigation stack time to finish its own initial load before this restores
/// `selectedItemId` from `SceneStorage` — restoring too early would navigate to an item the
/// list hasn't populated yet. See CODE_AUDIT §9.14.
/// (A plain file-private constant rather than a `static let` member: Swift doesn't support
/// stored `static` properties on the generic `ItemStateRestorationModifier<Route, Root>` below.)
private let stateRestorationDelay: Duration = .seconds(2)

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

enum ItemStateRestoration {
    /// The item to select once the restore delay is over: the stored one, and only while nothing is
    /// selected. Restoring blindly cleared a selection made during the delay (first selection after
    /// choosing a module, when nothing is stored), so the detail appeared and disappeared again.
    static func itemToRestore(stored: UUID?, current: UUID?) -> UUID? {
        current == nil ? stored : nil
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
    @Environment(\.navigator) private var navigator

    @SceneStorage private var selectedItemId: String?
    @SceneStorage private var displayMode: ListDisplayModel.DisplayMode
    @SceneStorage private var listMode: ListDisplayModel.ListMode

    @State private var route: Route?
    @State private var moduleRootNavigationDepth: Int?
    @State private var hasRestoredState = false

    func body(content: Content) -> some View {
        content
            .applyIf(appSizeModel.mode == .compact) {
                $0.navigate(to: $route)
            }
            .syncListDisplay(listControllable: root.folderListControllable, displayMode: $displayMode, listMode: $listMode)
            .onChange(of: navigator.count) { oldCount, newCount in
                guard appSizeModel.mode == .compact,
                      oldCount > newCount,
                      let moduleRootNavigationDepth,
                      newCount == moduleRootNavigationDepth else { return }
                route = nil
                selectedItemId = nil
                let listModel = root.folderListControllable.listModel
                listModel.resetNavigationSelection()
                root.navigationModel.selectedItemId = nil
            }
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
                if moduleRootNavigationDepth == nil {
                    moduleRootNavigationDepth = navigator.count
                }
            }
            .task {
                // Once per installed view, not on every appearance: the list reappears as soon
                // as an interactive swipe back starts, while the popped item is still stored
                // (the path only shrinks when the swipe completes) — a restore started then
                // pushed that item again after the delay.
                guard !hasRestoredState else { return }
                hasRestoredState = true

                // `@SceneStorage` may only be read/written while this view is
                // synchronously installed — touching it again after the `await`
                // below resumes on a detached continuation, which is exactly what
                // logs "Accessing a SceneStorage value outside of being installed
                // on a View". So snapshot (and clean up any corrupted value) here,
                // then only ever touch the plain snapshot after the delay.
                let restoredItemId = selectedItemId.flatMap(UUID.init(uuidString:))
                if selectedItemId != nil, restoredItemId == nil {
                    selectedItemId <=> nil
                }

                do {
                    try await Task.sleep(for: stateRestorationDelay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                // The user may have chosen an item during the delay (a module opened for the first
                // time has nothing stored): that choice is kept, never replaced by the old one.
                if let itemId = ItemStateRestoration.itemToRestore(
                    stored: restoredItemId,
                    current: root.navigationModel.selectedItemId
                ) {
                    root.navigationModel.selectedItemId = itemId
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

private extension EnvironmentValues {
    @Entry var itemStateRestorationEnabled: Bool = true
}

public extension View {
    func itemStateRestorationEnabled(_ enabled: Bool) -> some View {
        environment(\.itemStateRestorationEnabled, enabled)
    }
}
