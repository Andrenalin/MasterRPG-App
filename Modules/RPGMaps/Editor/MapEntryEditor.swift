// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import SwiftUI
import RPGValues
import RPGAudios
import RPGDie
import RPGPdfs
import PhotoRPG
import RPGTables

struct MapEntryEditor: View {
    let root: MapRootModel
    let editController: EditController
    
    @Environment(\.openWindow) private var openWindow
    
    @State private var showValueAdd: Bool = false
    @State private var linkValueData: [LinkData] = []
    @State private var linkEntryId: UUID = UUID()
    @State private var pinNumber = 1

    var body: some View {
        EntryEditor(editControllable: editController) {
            contentView()
        } linkActionView: {
            linkActionView()
        }
        .alert(Text("Add Value as Monster?", bundle: .module), isPresented: $showValueAdd, presenting: linkValueData) { linkData in
            //TextField("How many pins per value", value: $pinNumber, format: .number)
            
            Button {
                let pins = linkData.map {
                    ItemRowModel(itemId: $0.itemId, typeId: $0.module)
                }
                withAnimation {
                    editController.addMonsters(to: linkEntryId, monsters: pins, number: pinNumber)
                    editController.save(with: String(localized: "Add monsters").localizedString)
                }
            } label: {
                Text("Yes add \(pinNumber) Pin", bundle: .module)
            }
            
            Button {
                var content = editController.model[linkEntryId].content
                linkValueData.forEach { linkData in
                    content = root.valueRoot.linkController.generateLinks(itemId: linkData.itemId, entryId: linkData.entryId, into: content)
                }
                withAnimation {
                    editController.model[linkEntryId].content = content
                    editController.save(with: String(localized: "Drop link").localizedString)
                }
            } label: {
                Text("No only as Value", bundle: .module)
            }
        } message: { linkData in
            Text("Do you want to add the value:\n\(linkData.first?.name.withoutLink() ?? "Unnamed")\(linkData.count > 1 ? " and more" : "")\nas a monster pin, too?", bundle: .module)
        }
    }
    
    @ViewBuilder
    func linkActionView() -> some View {
        AltOpenWindowButton(module: .audio)
        AltOpenWindowButton(module: .dice)
        AltOpenWindowButton(module: .map)
        AltOpenWindowButton(module: .photo)
        AltOpenWindowButton(module: .table)
        AltOpenWindowButton(module: .value)
    }
    
    @ViewBuilder
    func contextMenuView(entryId: UUID) -> some View {
        ContextMenuEntryEditor(editControllable: editController, entryId: entryId) {
            Divider()
            
            Button {
                withAnimation {
                    editController.editorModel.currentEntryId = entryId
                    openWindow(id: WindowIdentifier.mapEditor.rawValue)
                }
            } label: {
                Text("Edit MapEntry \(String(editController.model[entryId].name.prefix(16)))", bundle: .module)
            }
        }
    }
    
    @ViewBuilder
    func contentView() -> some View {
        @Bindable var model = editController.model
        @Bindable var editorModel = editController.editorModel
        Table(editController.editEntries, selection: $editorModel.selected) {
            TableColumn(Text("Submap", bundle: .module)) { entry in
                EntryThumbnail(root: root, item: editController.model, entryId: entry.id)
            }
            .width(68)
            
            TableColumn(Text("Shown", bundle: .module)) { entry in
                ToggleEditor(editController: editController, model: $model[entry.id].isShown, bundle: .module)
                    .labelsHidden()
                    .labelsHidden()
            }
            .width(42)

            TableColumn(Text("Name", bundle: .module)) { entry in
                MapNameColumn(root: root, editController: editController, entryId: entry.id) {
                    contextMenuView(entryId: entry.id)
                }
            }
            .width(220)
            
            TableColumn(Text("Content", bundle: .module)) { entry in
                DropItemArea {
                    MapDescriptionColumn(root: root, editController: editController, entryId: entry.id) {
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
        var valueLinks: [LinkData] = []
        links.forEach { link in
            switch link.module {
            case .audio:
                content = root.audioRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .dice:
                content = root.diceRoot.linkController.generateLinks(itemId: link.itemId, into: content)
            case .map:
                content = root.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .pdf:
                content = root.pdfRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .photo:
                content = root.photoRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .table:
                content = root.tableRoot.linkController.generateLinks(itemId: link.itemId, entryId: link.entryId, into: content)
            case .value:
                valueLinks.append(link)
            default:
                unsupportedLinks += 1
            }
        }
        
        if !valueLinks.isEmpty {
            linkValueData = valueLinks
            linkEntryId = entryId
            showValueAdd.toggle()
        }
        
        withAnimation {
            editController.updateContent(content, for: entryId)
        }
        return unsupportedLinks == 0
    }
}
#endif
