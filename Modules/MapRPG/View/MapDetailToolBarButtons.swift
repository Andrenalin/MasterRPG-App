// @copyright André Trettin

import CoreRPG
import SwiftUI

struct QuickEditorButton: View {
    let model: MapModel
    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: MapEditorRoute.quickEditor(model.id))
        } label: {
            Label {
                Text("Quick Editor", bundle: .module)
            } icon: {
                Image(systemName: "table.badge.more")
            }
        }
    }
}

struct MapEditorButton: View {
    let model: MapModel
    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var sceneManager

    var body: some View {
        Button {
#if os(visionOS) || os(macOS)
            sceneManager.openWindow(.mapEditor)
#else
            navigator.navigate(to: MapEditorRoute.mapEditor(model.id))
#endif
        } label: {
            Label {
                Text("Map Editor", bundle: .module)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
        }
    }
}

struct EditTileButton: View {
    let model: MapModel
    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var sceneManager

    var body: some View {
        Button {
#if os(visionOS) || os(macOS)
            sceneManager.openWindow(.mapEditor)
#else
            navigator.navigate(to: MapEditorRoute.mapEditor(model.id))
#endif
        } label: {
            Label { Text("Edit Tile", bundle: .module) } icon: { Image(systemName: "skew") }
        }
    }
}

struct AddEntryButton: View {
    let root: MapRootModel
    let model: MapModel

    var body: some View {
        Button {
            withAnimation {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
                let entryId = root.editController.addNewEntry(itemId: model.id)
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

struct AddLinkButton: View {
    let root: MapRootModel
    let model: MapModel
    let module: NetworkModules
    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            withAnimation {
                navigator.navigate(to: MapEditorRoute.addLink(ItemRowModel(itemId: model.id, typeId: module)))
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
