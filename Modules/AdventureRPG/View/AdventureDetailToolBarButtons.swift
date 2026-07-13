// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif

#if !os(tvOS)
#Preview(traits: .mockData) { AdventureExtractToolBarButton(model: .preview) }
#endif
import SwiftUI

#if !os(tvOS)
struct AdventureExtractToolBarButton: View {
    let model: AdventureModel

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: AdventureDetailRoute.adventureExtraction(model.id), method: .managedSheet)
        } label: {
            Label {
                Text("Extract Information", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .disabled(model.entries.isEmpty)
    }
}
#endif

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
                root.editController.editorModel.sheetEditorModel.entryId = entryId
                Task {
                    try? await Task.sleep(for: .seconds(0.25))
                    root.editController.editorModel.sheetEditorModel.scrollEntryId = entryId
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

#Preview(traits: .mockData) { AdventureQuickEditorButton(model: .preview) }
#Preview(traits: .mockData) { AdventureAddEntryButton(root: .preview, model: .preview) }
#Preview(traits: .mockData) { AdventureAddLinkButton(root: .preview, model: .preview, module: .photo) }
