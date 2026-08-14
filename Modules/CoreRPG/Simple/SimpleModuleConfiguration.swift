// @copyright André Trettin

import Foundation
import UniformTypeIdentifiers

/// A minimal `ModuleConfigurable` for a ``SimpleSheetEditingSession``. The
/// session never browses a list/folder, imports/exports files, or resolves
/// file types, so those fields are inert placeholders — `module` is the only
/// field anything in the sheet-editing path actually reads (it tags the
/// `ItemRowModel`s the session's `SimpleSheetController` builds).
@MainActor
public struct SimpleModuleConfiguration: ModuleConfigurable {
    public init(module: NetworkModules) {
        self.module = module
    }

    public let module: NetworkModules
    public let categoryTags: [ItemListCategory] = [.item]
    public let fileTypes: [UTType] = []
    public let filenameExtension: String = ""
    public let collectionCategory: ItemListCategory = .collection
    public let linkSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
}
