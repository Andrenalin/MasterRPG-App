// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct EntryRow: View {
    let item: ItemRowTreeModel
    let isSelected: Bool
    
    @Environment(PhotoRootModel.self) private var root
    
    @Environment(\.gameModus) private var gameModus
    @Environment(\.showGame) private var showGame
    @Environment(\.mapActions) private var mapActions
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    
    @State private var showImage = false
    @State private var successMap: UUID? = nil
    @State private var showMapActionIndicator = false
    
    @State private var lastFileUrl: FileUrl?
    @State private var isLoading: Bool = false

    var itemId: UUID {
        item.model.entryId ?? item.model.itemId
    }
    
    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: itemId)
        
        VStack {
            quickMapActionView
            
            RotatePhotoView(image: cachedImage(for: model.id), degrees: model.degrees)
#if !os(tvOS)
                .onTapGesture { showImage.toggle() }
#endif
                .sheetFullScreen(isPresented: $showImage, idealSize: cachedImage(for: model.id)?.size ?? CGSize(width: 300, height: 200) + 100.0) {
                    RootPhotoViewer(model: model, toolBarModel: GameToolBarModel())
#if os(iOS)
                        .statusBar(hidden: true)
#endif
                }
        }
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
        .transition(.push(from: .leading))
        .animation(.linear, value: cachedImage(for: model.id))
        .onChange(of: model.fileUrl, initial: true) {
            guard !isLoading && (lastFileUrl != model.fileUrl || cachedImage(for: model.id) == nil) else { return }
            isLoading = true
            lastFileUrl = model.fileUrl
            loadImage(model: model)
        }
    }
    
    private func cachedImage(for itemId: UUID) -> AKImage? {
        cacheItemListModel.imageCache(cacheType: .image, itemId: itemId)
    }
    
    private var cacheItemListModel: CacheItemListModel {
        // image cache
        editController.cacheItemListModel
    }
    
    private var editController: EditController {
        root.editController
    }

    private func loadImage(model: PhotoModel) {
        Task { @MainActor in
            let loaderTask = Task.detached(priority: .userInitiated) {
                await editController.loadImage(cacheType: .image, itemId: model.id, fileUrl: model.fileUrl)
            }
            _ = await loaderTask.result
            isLoading = false
        }
    }
    
    private var quickMapActionView: some View {
        HStack {
            Button {
                Task {
                    await networkActions?.game(root.gameController.share(id: itemId), .photoSpace)
                }
            } label: {
                Image(systemName: "visionpro.and.arrow.forward")
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.teal, .white)
            }
            .opacity((showGame && gameModus == .master) ? 1 : 0)
            .buttonStyle(.bordered)
            .contentShape(Rectangle())

            Spacer()

            Text("Create")
                .opacity(gameModus == .player ? 0 : 1)

            Button {
                Task {
                    successMap = await mapActions.quickMap(root.itemController.itemOrEmpty(for: itemId).name, itemId)
                    withAnimation { showMapActionIndicator = true }
                }
            } label: {
                Image(systemName: NetworkModules.map.icon)
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.teal, .white)
            }
            .opacity(gameModus == .player ? 0 : 1)
            .borderLessTVBottonStyle(notMac: true)
            .contentShape(Rectangle())
            .alert("Quick Map", isPresented: $showMapActionIndicator) {
                Button {
                    withAnimation {
                        showMapActionIndicator = false
                        routeActions.routePage(.map, successMap, nil)
                    }
                } label: {
                    Text("Show map", bundle: .module)
                }
                
                Button {
                    showMapActionIndicator = false
                } label: {
                    Text("Ok", bundle: .module)
                }
            } message: {
                Text(successMap != nil ? "The map is created sucessfully." : "Failed to create a map.", bundle: .module)
            }
        }
    }
}

#Preview {
    EntryRow(item: .preview, isSelected: true)
        .environment(PhotoRootModel.previewWithData)
}
