// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import os.log

struct AsyncPhoto<Content: View>: View {
    init(model: PhotoModel, @ViewBuilder content: @escaping (AKImage, Double) -> Content) {
        self.model = model
        self.content = content
    }
    
    let model: PhotoModel
    let content: (AKImage, Double) -> Content
    
    @Environment(PhotoRoot.self) private var root
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    @State private var imageError: Bool = false
    
    var body: some View {
        VStack {
            if let image = cachedImage(for: model.id) {
                content(image, model.degrees)
            } else if imageError {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    Text("Wait for image ...", bundle: .module)
                        .font(.largeTitle)
                    
                    ProgressView().progressViewStyle(.circular).tint(.teal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onChange(of: model.fileUrl, initial: true) {
            loadImage()
        }
    }
    
    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheItemListModel.imageCache(cacheType: .image, itemId: itemId)
    }
    
    private var cacheItemListModel: CacheItemListModel {
        // image cache
        root.editController(type: .main).cacheItemListModel
    }

    private func loadImage() {
        Task { @MainActor in
            let loaderTask = Task.detached(priority: .userInitiated) {
                await root.editController(type: .main).loadImage(cacheType: .image, itemId: model.id, fileUrl: model.fileUrl)
            }
            _ = await loaderTask.result
            if cachedImage(for: model.id) == nil {
                imageError = true
                Logger.itemController.warning("AsyncPhoto: No image \(model.id, privacy: .public)")
            } else {
                imageError = false
            }
            isLoading = false
        }
    }
}


struct AsyncPhotoViewer: View {
    let model: PhotoModel
    let size: CGSize
    let contentMode: ContentMode

    @Environment(PhotoRoot.self) private var root

    @State private var isLoading: Bool = false
    @State private var imageError: Bool = false

    var body: some View {
        VStack {
            if let image = cachedImage(for: model.id) {
                Image(akImage: image)
                    .resizable()
                    .rotationEffect(Angle(degrees: model.degrees))
                    .applyIf(contentMode == .fit) { content in
                        content
                            .aspectRatio(contentMode: contentMode)
                            .clipShape(.rect(cornerRadius: 16))
                            .frame(width: size.width, height: size.height, alignment: .center)
                    }
            } else if imageError {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    Text("Wait for image ...", bundle: .module)
                        .font(.largeTitle)

                    ProgressView().progressViewStyle(.circular).tint(.teal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onChange(of: model.fileUrl, initial: true) {
            loadImage()
        }
    }

    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheItemListModel.imageCache(cacheType: .image, itemId: itemId)
    }

    private var cacheItemListModel: CacheItemListModel {
        root.editController(type: .main).cacheItemListModel
    }

    private func loadImage() {
        Task { @MainActor in
            let loaderTask = Task.detached(priority: .userInitiated) {
                await root.editController(type: .main).loadImage(cacheType: .image, itemId: model.id, fileUrl: model.fileUrl)
            }
            _ = await loaderTask.result
            if cachedImage(for: model.id) == nil {
                imageError = true
                Logger.itemController.warning("AsyncPhotoViewer: No image \(model.id, privacy: .public)")
            } else {
                imageError = false
            }
            isLoading = false
        }
    }
}

#Preview {
    AsyncPhoto(model: .preview) {
        Image(akImage: $0)
            .rotationEffect(Angle(degrees: $1))
    }
    .environment(PhotoRoot.preview)
}
