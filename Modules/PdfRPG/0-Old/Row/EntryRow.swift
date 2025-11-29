// @copyright André Trettin

import CoreRPG
import SwiftUI

#if !os(tvOS)
import PDFKit
#endif

struct EntryRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel
    
#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    @Environment(PdfRootModel.self) private var root
    @Environment(ListModel.self) private var itemListModel
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel
    
    private var entry: PdfEntryModel? {
        guard let entryId = item.model.entryId, entryId != item.model.itemId else { return nil }
        return root.itemController.itemOrEmpty(for: item.model.itemId)[entryId]
    }
    
    private var entryId: UUID {
        item.model.entryId ?? item.model.itemId
    }
    
    var body: some View {
        //let _ = Self._printChanges()
        
        VStack(alignment: .leading, spacing: 8) {
            ImageOverlayButton(icon: entry != nil ? "bookmark" :  root.itemController.itemDataModel.networkModule.icon) {
#if os(visionOS) || os(macOS)
                openWindow(id: WindowIdentifier.pdfViewer.rawValue, value: ItemSelection(itemId: item.model.itemId, entryId: item.model.entryId))
#else
                withAnimation {
                    selectionSheetLinkModel.selectionFullView = AnyView(                root.viewController.pdfWindow(root: root, selection: ItemSelection(itemId: item.model.itemId, entryId: item.model.entryId))
                        .environment(\.showGame, false))
                    selectionSheetLinkModel.selectionFullScreen = true
                }
#endif
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if entry != nil {
                LinkHighlightTextView(model: linkTextModel)
                    .lineLimit(10)
            } else {
                Text("No bookmark added yet", bundle: .module)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) else {
            return updateLinkText()
        }
        return linkModel
    }
    
    @discardableResult
    private func updateLinkText() -> LinkHighlightTextModel {
        var entryText: String = ""
        if let entry {
            entryText = "**\(entry.pageLabel) - \(entry.name)**: \(entry.content)"
        }
        if let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: itemListModel.searchText, toggler: nil, shareResult: nil, editAction: nil)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }
}

#Preview {
    EntryRow(item: .preview, isSelected: true, cacheItemListModel: .preview)
        .environment(PdfRootModel.preview)
        .environment(ListModel.preview)
        .environment(\.locale, .init(identifier: "de"))
}
