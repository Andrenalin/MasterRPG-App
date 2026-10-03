// @copyright André Trettin

import SwiftUI

/// Gives a detail route destination one list controller for the parent folder of `itemId`, kept
/// for as long as the destination shows that item in that folder.
///
/// The destinations built the controller (`copy(listModel:)`) inside `body`. The body reads the
/// module's items, so every insert or removal handed the detail view a fresh controller with an
/// empty list, search and display model: open folders, selection, scroll position and filter
/// text reset. See CODE_AUDIT_Folder §8.1.
public struct DetailFolderControllerReader<Controller: FolderListControllable, Content: View>: View {
    public init(
        listController: Controller,
        itemId: UUID,
        parentModel: any ItemDataAccessible,
        navigationModel: ModuleNavigationModel,
        @ViewBuilder content: @escaping (Controller) -> Content
    ) {
        self.listController = listController
        self.itemId = itemId
        self.parentModel = parentModel
        self.navigationModel = navigationModel
        self.content = content
    }

    private let listController: Controller
    private let itemId: UUID
    private let parentModel: any ItemDataAccessible
    private let navigationModel: ModuleNavigationModel
    private let content: (Controller) -> Content

    /// A plain box, not observed: filling it while `body` runs does not invalidate the view.
    @State private var store = DetailControllerStore<Controller>()

    public var body: some View {
        content(store.controller(itemId: itemId, parentModel: parentModel) {
            listController.copy(listModel: FolderListModel(parentModel: parentModel, navigationModel: navigationModel))
        })
    }
}

/// Public only because the reader stores it in `@State`: other modules lay out the reader and
/// reference this type's metadata. Its members stay internal.
@MainActor
public final class DetailControllerStore<Controller: FolderListControllable> {
    init() {}

    private struct Key: Equatable {
        let itemId: UUID
        let parentId: UUID
    }

    private var key: Key?
    private var current: Controller?

    /// The kept controller while the item and its folder stay the same, else a new one from
    /// `make`. The folder model is refreshed in place: a sync may have replaced its instance.
    func controller(itemId: UUID, parentModel: any ItemDataAccessible, make: () -> Controller) -> Controller {
        let key = Key(itemId: itemId, parentId: parentModel.id)
        if let current, self.key == key {
            current.listModel.parentModel = parentModel
            return current
        }
        let controller = make()
        self.key = key
        current = controller
        return controller
    }
}
