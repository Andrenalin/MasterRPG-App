// @copyright André Trettin

import AndrenalinKit
import SwiftUI
internal import UniformTypeIdentifiers

struct PdfEditor: View {
    let editController: EditController
    let size: CGSize
    let topMargin: CGFloat
    let inline: Bool
    
    @Environment(PdfRoot.self) private var root
    @Environment(ListModel.self) private var itemListModel
    
    @State private var thumbnail: AKImage?
    @State private var showImporter = false
    
    var body: some View {
        @Bindable var model = editController.model
        VStack(alignment: .center) {
            HeaderPhoto(itemId: imageId, image: thumbnail, degrees: 0, size: size, topMargin: topMargin)
                .frame(maxWidth: .infinity, alignment: .center)
#if os(iOS)
                .toolbar {
                    ToolbarItem {
                        if inline == false {
                            overlayButton
                        }
                    }
                }
#else
                .overlay(alignment: .topTrailing) {
                    overlayButton
                        .padding([.top, .trailing])
                }
#endif
#if !os(tvOS)
                .overlay(alignment: .bottomTrailing) {
                    if inline == false {
                        PdfImporterButtonView(showImporter: $showImporter)
                            .padding([.trailing, .bottom])
                    }
                }
#endif
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            guard let url = try? result.get() else { return }
            editController.resetPdf(url: url)
        }
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: [.pdf], updateFile: updatePdf))
#endif
        .onChange(of: editController.model.fileUrl, initial: true) {
            guard editController.model.fileUrl != nil else {
                withAnimation { thumbnail = nil }
                return
            }
            loadImage(for: editController.model.id)
        }
        .onChange(of: itemListModel.selectedItem, initial: false) {
            guard editController.model.fileUrl != nil else {
                withAnimation { thumbnail = nil }
                return
            }
            loadImage(for: editController.model.id)
        }
    }
    
    private var overlayButton: some View {
        ShowQuickLook(listController: root.listController(model: itemListModel), windowId: WindowIdentifier.pdfViewer.rawValue, useInternal: true, useSelection: nil) { model in
            root.itemController.itemOrEmpty(for: model.itemId).hasPdf
        } content: { model in
            root.viewController.pdfWindow(selection: ItemSelection(itemId: model.itemId, entryId: model.entryId))
                .environment(\.showGame, false)
        }
    }
    
    private var imageId: Binding<UUID?> {
        Binding {
            editController.model.id
        } set: { _ in
            // never set
        }
    }
    
    private func loadImage(for id: UUID) {
        Task {
            await root.cacheController.thumbnailId(for: id, with: editController.model.fileUrl, shouldDownload: true)
            let newImage = await root.cacheController.thumbnail(for: id)
            if editController.model.id == id {
                withAnimation { thumbnail = newImage }
            }
        }
    }
    
    private func updatePdf(url: URL) {
        editController.resetPdf(url: url)
    }
}

#Preview {
    PdfEditor(editController: .preview, size: CGSize(width: 300, height: 200), topMargin: 64, inline: false)
        .environment(PdfRoot.preview)
}
