//// @copyright André Trettin
//
//import CoreRPG
//import SwiftUI
//import os.log
//
//struct AsyncImageViewer: View {
//    let model: ItemDataModel
//    let size: CGSize
//    let toolBarModel: GameToolBarModel
//
//    @Environment(PhotoRootModel.self) private var root
//
//    @Environment(\.dismiss) private var dismiss
//
//    @State private var lastFileUrl: FileUrl?
//    @State private var isLoading: Bool = false
//
//    @State private var imageError: Bool = false
//    @State private var degrees: Double = 0
//
//    var body: some View {
//        let _ = Self._printChanges()
//        VStack {
//            if let image = cachedImage(for: model.id) {
//                ImageViewer(image: image, photoDegrees: degrees, containerSize: size, toolBarModel: toolBarModel)
//            } else if imageError {
//                VStack(alignment: .center, spacing: 20) {
//                    Spacer()
//                    Text("Wait for image ...", bundle: .module)
//                        .font(.largeTitle)
//
//                    ProgressView().progressViewStyle(.circular).tint(Color.accentColor)
//                    Spacer()
//                }
//                .frame(maxWidth: .infinity, alignment: .center)
//            }
//        }
//        .onChange(of: model.fileUrl, initial: true) {
//            loadImage()
//        }
//    }
//
//    private func cachedImage(for itemId: UUID) -> AKImage? {
//        cacheItemListModel.imageCache(cacheType: .image, itemId: itemId)
//    }
//
//    private var cacheItemListModel: CacheItemListModel {
//        root.listControllable.cacheListItemModel
//    }
//
//    func loadImage() {
//        Task { @MainActor in
//            let fileId = model.id
//            let fileUrl = model.fileUrl
//            let loaderTask = Task.detached(priority: .userInitiated) {
//                await root.cacheController.photoId(for: fileId, with: fileUrl, shouldDownload: false)
//            }
//            _ = await loaderTask.result
//            let newImage = await root.cacheController.photo(for: fileId)
//            withAnimation { cacheItemListModel.setImageCache(cacheType: .image, itemId: fileId, image: newImage) }
//            isLoading = false
//            if newImage == nil {
//                imageError = true
//                Logger.itemController.warning("AsyncImageViewer: No image \(fileId, privacy: .public)")
//            } else {
//                imageError = false
//            }
//        }
//    }
//}
