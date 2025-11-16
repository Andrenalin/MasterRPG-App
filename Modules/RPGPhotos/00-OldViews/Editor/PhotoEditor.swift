// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import UniformTypeIdentifiers

struct PhotoEditor: View {
    let editController: EditController

    @Environment(PhotoRootModel.self) private var root
    @Environment(ListModel.self) private var itemListModel
    @Environment(DetailHeaderModel.self) private var headerModel

    @State private var showImporter = false
    
    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false
    
    var body: some View {
        @Bindable var model = editController.model        
        VStack {
            HeaderPhoto(itemId: imageId, image: editController.cacheItemListModel.imageCache(cacheType: .image, itemId: editController.model.id), degrees: editController.model.degrees, size: headerModel.size, topMargin: headerModel.topSafeAreaHeight)
                .overlay {
                    if isLoading {
                        Color.black.opacity(0.3)
                            .overlay(alignment: .center) {
                                ProgressView()
                                    .tint(Color.accentColor)
#if !os(tvOS)
                                    .controlSize(.large)
#endif
                            }
                    }
                }
#if os(iOS)
                .toolbar {
                    ToolbarItem {
                        if headerModel.isInline == false {
                            photoButton
                        }
                    }
                }
#else
                .overlay(alignment: .topTrailing) {
                    photoButton
                        .padding([.top, .trailing])
                }
#endif
#if !os(tvOS)
                .overlay(alignment: .bottomTrailing) {
                    if headerModel.isInline == false {
                        PhotoImporterView(showImporter: $showImporter, updateImage: updateImage(image:))
                        .padding([.trailing, .bottom])
                    }
                }
#endif
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            editController.resetPhoto(url: url)
        }
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: [.image], updateFile: updatePhoto))
#endif
        .onChange(of: editController.model.fileUrl, initial: true) {
            guard !isLoading && (lastFileUrl != model.fileUrl || cachedImage(for: model.id) == nil) else { return }
            loadImage()
        }
    }
}

private extension PhotoEditor {
    private var imageId: Binding<UUID?> {
        Binding {
            editController.model.id
        } set: { _ in
            // never set
        }
    }
    
    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheItemListModel.imageCache(cacheType: .image, itemId: itemId)
    }
    
    private var cacheItemListModel: CacheItemListModel {
        // image cache
        editController.cacheItemListModel
    }
    
    private func loadImage() {
        Task { @MainActor in
            isLoading = true
            let reset = lastFileUrl != editController.model.fileUrl
            lastFileUrl = editController.model.fileUrl
            
            let loaderTask = Task.detached(priority: .userInitiated) {
                await editController.loadImage(cacheType: .image, itemId: editController.model.id, fileUrl: editController.model.fileUrl, reset: reset)
            }
            _ = await loaderTask.result
            isLoading = false
        }
    }
    
    func updatePhoto(url: URL) {
        editController.resetPhoto(url: url)
    }
    
    @Sendable func updateImage(image: AKImage?) async {
        await editController.resetPhoto(image: image)
    }
    
    var photoButton: some View {
        ShowQuickLook(listController: root.listController(model: itemListModel), windowId: WindowIdentifier.photoViewer.rawValue) { model in
            root.itemController.itemOrEmpty(for: model.itemId).hasPhoto
        } content: { model in
            root.viewController.photoWindow(root: root, selection: ItemSelection(itemId: model.itemId, entryId: model.entryId))
        }
    }
}

#Preview {
    PhotoEditor(editController: .preview)
        .environment(PhotoRootModel.preview)
        .environment(DetailHeaderModel())
        .environment(ListModel.preview)
}
