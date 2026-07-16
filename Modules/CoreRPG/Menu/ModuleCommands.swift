// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
public struct ModuleCommands: Commands {
    public init(root: any ItemRootControllable, scenesManager: ScenesManager, routeActions: RouteActions, key: AKKeyEquivalent) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
        self.key = key
    }

    let root: any ItemRootControllable
    let scenesManager: ScenesManager
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?
    @FocusedValue(\.listDisplayModel) private var listDisplayModel: ListDisplayModel?
    @FocusedValue(\.selectedSheetEntry) private var selectedSheetEntry: SelectedSheetEntry?

    public var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(networkModule: root.configurable.module, scenesManager: scenesManager, key: key)
        }
        CommandGroup(after: .toolbar) {
            NavigateButton(root: root, routeActions: routeActions, key: key)
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root, routeActions: routeActions, key: key)
            AddFolderButton(root: root, routeActions: routeActions, key: key)
            AddCollectionButton(root: root, routeActions: routeActions, key: key)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == root.configurable.module {
                SpaceActionButton(root: root, scenesManager: scenesManager)
                EditItemButton(root: root)
                DuplicateItemButton(root: root)
                ExportItemButton(root: root)
                GroupEditorButton(root: root)
                if root.viewControllable.supportsBatchExtraction {
                    BatchExtractionButton(root: root)
                }
                Divider()
                AddItemIntoButton(root: root)
                MoveItemIntoButton(root: root)
                Divider()
                DeleteItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(after: .textEditing) {
            if selectedModule == root.configurable.module,
               let selectedSheetEntry, selectedSheetEntry.entryModel.source.typeId == root.configurable.module {
                SheetEntryEditButton(rootModel: selectedSheetEntry.rootModel, entryModel: selectedSheetEntry.entryModel, parentModel: selectedSheetEntry.parentModel, isEditor: selectedSheetEntry.isEditor, onlyIcon: false)
                SheetContextMenuView(rootModel: selectedSheetEntry.rootModel, parentModel: selectedSheetEntry.parentModel, entryModel: selectedSheetEntry.entryModel, isEditor: selectedSheetEntry.isEditor)
                SheetEntryDeleteButton(rootModel: selectedSheetEntry.rootModel, parentModel: selectedSheetEntry.parentModel, entryModel: selectedSheetEntry.entryModel, onlyIcon: false)
            }
        }
        CommandGroup(replacing: .undoRedo) {
            if selectedModule == root.configurable.module {
                UndoButton(root: root)
                RedoButton(root: root)
            }
        }
        CommandGroup(before: .sidebar) {
            if selectedModule == root.configurable.module, let listDisplayModel {
                MenuDisplayModeToggle(listDisplayModel: listDisplayModel, showSelectionButton: true)
                Divider()
                OpenFolderButton(root: root)
                CloseFolderButton(root: root)
                Divider()
            }
        }
    }
}
#endif
