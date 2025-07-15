// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PhotoImporterView: View {
    let model: PhotoDataModel

    var body: some View {
        ViewThatFits {
            HStack(spacing: 40) {
                contentView
            }

            VStack(spacing: 40) {
                contentView
            }
        }
    }
    
    @ViewBuilder
    var contentView: some View {
        CameraImporterView(model: model, size: 80)
        FileImporterView(model: model, size: 80)
        LibraryImporterView(model: model, size: 80)
    }
}

struct CameraImporterView: View {
    init(model: PhotoDataModel, size: CGFloat = 24) {
        self.model = model
        self.size = size
        self.modelActor = model.modelActor()
    }

    let model: PhotoDataModel
    let modelActor: PhotoDataModelActor?
    let size: CGFloat
    
    @Environment(PhotoRootModel.self) private var rootModel
    
    @State private var showCamera = false
    
    var body: some View {
#if os(iOS)
        GlassButton {
            showCamera.toggle()
        } label: {
            Image(systemName: "camera\(showCamera ? ".fill" : "")")
                .font(.system(size: size))
                .padding(size / 3)

        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
        .opacity(CaptureImagePicker.isCameraAvailable ? 1 : 0)
        
        .sheet(isPresented: $showCamera) {
            CaptureImagePicker(shown: $showCamera) { [id = model.id] image in
                await update(id: id, image: image)
            }
        }
#endif
    }
    
    private func update(id: UUID, image: AKImage?) async {
        guard let modelActor else { return }
        let editController = EditController(root: rootModel)
        await editController.resetPhoto(image: image, id: id, actor: modelActor)
    }
}

struct FileImporterView: View {
    let model: PhotoDataModel
    let size: CGFloat
    
    @Environment(PhotoRootModel.self) private var rootModel
    
    @State private var showImporter = false
    
    init(model: PhotoDataModel, size: CGFloat = 24) {
        self.model = model
        self.size = size
    }
    
    var body: some View {
#if !os(tvOS)
        GlassButton {
            showImporter.toggle()
        } label: {
            Image(systemName: "folder\(showImporter ? ".fill" : "")")
                .font(.system(size: size))
                .padding(size / 3)
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            let editController = EditController(root: rootModel)
            editController.resetPhoto(url: url, in: model)
        }
#endif
    }
}

struct LibraryImporterView: View {
    init(model: PhotoDataModel, size: CGFloat = 32) {
        self.model = model
        self.size = size
        self.modelActor = model.modelActor()
    }
    
    let model: PhotoDataModel
    let modelActor: PhotoDataModelActor?
    let size: CGFloat
    
    @Environment(PhotoRootModel.self) private var rootModel
    
    var body: some View {
        LibraryPhotoPicker(size: size) { [id = model.id] image in
            await update(id: id, image: image)
        }
    }
    
    private func update(id: UUID, image: AKImage?) async {
        guard let modelActor else { return }
        let editController = EditController(root: rootModel)
        await editController.resetPhoto(image: image, id: id, actor: modelActor)
    }
}



#Preview(traits: .mockData) {
    @Previewable @Query var photos: [PhotoDataModel]
    VStack {
        Color
            .teal
            .frame(width: 256, height: 256)
            .overlay(CameraImporterView(model: photos[0]), alignment: .bottom)
            .overlay(FileImporterView(model: photos[0]), alignment: .top)
            .overlay(LibraryImporterView(model: photos[0]), alignment: .center)
        
        PhotoImporterView(model: photos[0])
    }
    .environment(PhotoRootModel())
}
