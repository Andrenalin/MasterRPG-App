// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import SwiftUI

struct AdventureEntryEditor: View {
    let root: AdventureRoot
    let editController: EditController

    var body: some View {
        EntryEditor(editControllable: editController) {
            contentView()
        } linkActionView: {
            linkActionView()
        }
    }
    
    @ViewBuilder
    func linkActionView() -> some View {
        AltOpenWindowButton(module: .audio)
        AltOpenWindowButton(module: .dice)
        AltOpenWindowButton(module: .map)
        AltOpenWindowButton(module: .pdf)
        AltOpenWindowButton(module: .photo)
        AltOpenWindowButton(module: .space)
        AltOpenWindowButton(module: .table)
        AltOpenWindowButton(module: .value)
        AltOpenWindowButton(module: .weather)
    }
    
    @ViewBuilder
    func contextMenuView(entryId: UUID) -> some View {
        ContextMenuEntryEditor(editControllable: editController, entryId: entryId) {
            Button {
                withAnimation { editController.collectPhotos(entryId: entryId) }
            } label: {
                Text("Collect Photo Links", bundle: .module)
            }
        }
    }
    
    @ViewBuilder
    func contentView() -> some View {
        @Bindable var item = editController.model
        @Bindable var editorModel = editController.editorModel
        Table(item.entries, selection: $editorModel.selected) {
            TableColumn(Text("Name", bundle: .module)) { entry in
                AdventureNameColumn(root: root, editController: editController, entryId: entry.id) {
                    contextMenuView(entryId: entry.id)
                }
            }
            .width(200)
            
            TableColumn(Text("Content", bundle: .module)) { entry in
                DropItemArea {
                    AdventureContentColumn(root: root, editController: editController, entryId: entry.id) {
                        contextMenuView(entryId: entry.id)
                    }
                } dropAction: { linkData in
                    drop(links: linkData, entryId: entry.id)
                }
            }
            .width(min: 32)
        }
    }
    
    func drop(links: [LinkData], entryId: UUID) -> Bool {
        var content = editController.model[entryId].content
        var unsupportedLinks = 0
        links.forEach { link in
            switch link.module {
            case .adventure:
                content = root.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .audio:
                content = root.audioRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .dice:
                content = root.diceRoot.linkController.generateLinks(itemId: link.itemId, into: content)
            case .map:
                content = root.mapRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .pdf:
                content = root.pdfRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .photo:
                content = root.photoRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .space:
                content = root.spaceRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .table:
                content = root.tableRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .value:
                content = root.valueRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .weather:
                content = root.weatherRoot.linkController.generateLinks(itemId: link.itemId, into: content)
            default:
                unsupportedLinks += 1
            }
        }
        withAnimation {
            editController.updateContent(content, for: entryId)
        }
        return unsupportedLinks == 0
    }
}

#Preview {
    AdventureEntryEditor(root: .preview, editController: .preview)
        .padding()
        .environment(AdventureRoot.preview)
        .environment(ListModel.preview)
}

#endif
