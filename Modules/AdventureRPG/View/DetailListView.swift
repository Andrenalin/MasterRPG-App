// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailListView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.adventure.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }

    var body: some View {
        DetailFolderListView(root: root, model: model)
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

    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            if !model.specialCategory && !openFileWindowModel.showItem {
                ControlGroup {
                    AdventureQuickEditorButton(model: model)
                    AdventureAddEntryButton(root: root, model: model)
#if !os(tvOS)
                    AdventureAIAssistantButton(root: root, model: model)
#endif
                }
            }
        }
#if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            ForEach(root.editorLinkModel.firstRow, id: \.self) { module in
                AdventureAddLinkButton(root: root, model: model, module: module)
            }
        }
#endif
    }
}

// MARK: - Toolbar Buttons

struct AdventureQuickEditorButton: View {
    let model: AdventureModel
    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: EditorRoute.quickEditor(model.id))
        } label: {
            Label {
                Text("Quick Editor", bundle: .module)
            } icon: {
                Image(systemName: "table.badge.more")
            }
        }
    }
}

struct AdventureAddEntryButton: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        Button {
            withAnimation {
                let entryId = root.editController.addNewEntry(itemId: model.id)
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, entryId: entryId, typeId: root.config.module))
                root.editController.editorModel.currentEntryId = entryId
                Task {
                    try? await Task.sleep(for: .seconds(0.25))
                    root.editController.editorModel.scrollEntryId = entryId
                }
            }
        } label: {
            Label {
                Text("Add new Entry", bundle: .module)
            } icon: {
                Image(systemName: "note.text.badge.plus")
            }
        }
    }
}

struct AdventureAIAssistantButton: View {
    let root: AdventureRootModel
    let model: AdventureModel
    @Environment(\.navigator) private var navigator
#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    var body: some View {
        Button {
#if os(visionOS) || os(macOS)
            openWindow(id: WindowIdentifier.generateAdventure.rawValue)
#else
            navigator.navigate(to: EditorRoute.generator(model.id))
#endif
        } label: {
            Label {
                Text("AI Assistant", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
    }
}

struct AdventureAddLinkButton: View {
    let root: AdventureRootModel
    let model: AdventureModel
    let module: NetworkModules
    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            withAnimation {
                navigator.navigate(to: EditorRoute.addLink(ItemRowModel(itemId: model.id, typeId: module)))
            }
        } label: {
            Label {
                Text("Link", bundle: .module)
            } icon: {
                Image(systemName: module.icon)
            }
        }
    }
}
