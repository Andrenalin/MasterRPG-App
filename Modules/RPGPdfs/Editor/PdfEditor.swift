// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import UniformTypeIdentifiers

struct PdfEditor: View {
    let editController: EditController

    @Environment(PdfRoot.self) private var root
    @Environment(ListModel.self) private var itemListModel
    @Environment(DetailHeaderModel.self) private var headerModel

    @State private var thumbnail: AKImage?
    @State private var showImporter = false
    
    var body: some View {
        @Bindable var model = editController.model
        VStack(alignment: .center) {
            HeaderPhoto(itemId: imageId, image: thumbnail, degrees: 0, size: headerModel.size, topMargin: headerModel.topSafeAreaHeight)
                .frame(maxWidth: .infinity, alignment: .center)
#if os(iOS)
                .toolbar {
                    ToolbarItem {
                        if headerModel.isInline == false {
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
                    if headerModel.isInline == false {
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
        ShowQuickLook(listController: root.listController(model: itemListModel), windowId: WindowIdentifier.pdfViewer.rawValue) { model in
            root.itemController.itemOrEmpty(for: model.itemId).hasPdf
        } content: { model in
            root.viewController.pdfWindow(root: root, selection: ItemSelection(itemId: model.itemId, entryId: model.entryId))
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
            await root.cacheController?.thumbnailId(for: id, with: editController.model.fileUrl)
            let newImage = await root.cacheController?.thumbnail(for: id)
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
    PdfEditor(editController: .preview)
        .environment(PdfRoot.preview)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
        .environment(DetailHeaderModel(size: CGSize(width: 400, height: 200), topSafeAreaHeight: 0, isInline: false))
}
