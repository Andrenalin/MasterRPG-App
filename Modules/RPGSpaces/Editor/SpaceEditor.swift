// @copyright André Trettin

import AndrenalinKit
import SwiftUI
internal import UniformTypeIdentifiers

struct SpaceEditor: View {
    let editController: EditController

    @Environment(SpaceRoot.self) private var root
    @Environment(DetailHeaderModel.self) private var headerModel

    @State private var thumbnail: AKImage?
    @State private var showImporter = false

    var body: some View {
        @Bindable var model = editController.model
        
        VStack {
            HeaderPhoto(itemId: imageId, image: thumbnail, degrees: 0, size: headerModel.size, topMargin: headerModel.topSafeAreaHeight)
#if !os(tvOS)
#if os(iOS)
            .toolbar {
                ToolbarItem {
                    if headerModel.isInline == false {
                        SpaceQuickLook(root: root, item: ItemSelection(itemId: model.id, entryId: nil), startLoading: false, gameMode: false, dismiss: nil)
                    }
                }
            }
#else
            .overlay(alignment: .topTrailing) {
                SpaceQuickLook(root: root, item: ItemSelection(itemId: model.id, entryId: nil), startLoading: false, gameMode: false, dismiss: nil)
                    .padding([.top, .trailing])
            }
#endif
                .overlay(alignment: .bottomTrailing) {
                    if headerModel.isInline == false {
                        SpaceImporterView(showImporter: $showImporter)
                            .padding([.trailing, .bottom])
                    }
                }
#endif
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.usdz]) { result in
            guard let url = try? result.get() else { return }
            editController.resetSpace(url: url)
        }
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: [.usdz], updateFile: updateSpace))
#endif
        .onChange(of: editController.model.fileUrl, initial: true) {
            guard editController.model.fileUrl != nil else {
                withAnimation { thumbnail = nil }
                return
            }
            loadImage()
        }
    }
    
    private var imageId: Binding<UUID?> {
        Binding {
            editController.model.id
        } set: { _ in
            // never set
        }
    }

    private func loadImage() {
        Task {
            await root.cacheController.thumbnailId(for: editController.model.id, with: editController.model.fileUrl, shouldDownload: true)
            let newImage = await root.cacheController.thumbnail(for: editController.model.id)
            withAnimation { thumbnail = newImage }
        }
    }

    private func updateSpace(url: URL) {
        editController.resetSpace(url: url)
    }
}

#Preview {
    SpaceEditor(editController: .preview)
        .environment(SpaceRoot.preview)
        .environment(DetailHeaderModel(size: CGSize(width: 500, height: 300), topSafeAreaHeight: 0, isInline: false))
}
