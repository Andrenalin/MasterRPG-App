// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureQuickEditorButton: View {
    let model: AdventureModel
    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: AdventureEditorRoute.quickEditor(model.id))
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
                root.editController.sheetEditorModel.entryId = entryId
                Task {
                    try? await Task.sleep(for: .seconds(0.25))
                    root.editController.sheetEditorModel.scrollEntryId = entryId
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
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        Button {
#if os(visionOS) || os(macOS)
            scenesManager.openWindow(.generateAdventure)
#else
            navigator.navigate(to: AdventureEditorRoute.generator(model.id))
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
                navigator.navigate(to: AdventureEditorRoute.addLink(ItemRowModel(itemId: model.id, typeId: module)))
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
