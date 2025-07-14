// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CameraImporterView: View {
    let model: PhotoDataModel
    
    @State private var showCamera = false
    
    var body: some View {
#if !os(tvOS)
#if os(iOS)
        GlassButton {
            showCamera.toggle()
        } label: {
            Image(systemName: "camera\(showCamera ? ".fill" : "")")
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
        .opacity(CaptureImagePicker.isCameraAvailable ? 1 : 0)
        
        .sheet(isPresented: $showCamera) {
            CaptureImagePicker(shown: $showCamera, updateImage: update(image:))
        }
#endif
#endif
    }
    
    private func update(image: AKImage?) async {
        
    }
}

struct FolderImporterView: View {
    let model: PhotoDataModel
    
    @Environment(PhotoRootModel.self) private var rootModel
    
    @State private var showImporter = false
    
    var body: some View {
#if !os(tvOS)
        GlassButton {
            showImporter.toggle()
        } label: {
            Image(systemName: "folder\(showImporter ? ".fill" : "")")
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
    init(model: PhotoDataModel) {
        self.model = model
        self.modelActor = model.modelActor()
    }
    
    let model: PhotoDataModel
    let modelActor: PhotoDataModelActor?
    
    @Environment(PhotoRootModel.self) private var rootModel
    
    var body: some View {
        LibraryPhotoPicker { [id = model.id] image in
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
    Color
        .teal
        .frame(width: 256, height: 256)
        .overlay(CameraImporterView(model: photos[0]), alignment: .bottom)
        .overlay(FolderImporterView(model: photos[0]), alignment: .top)
        .overlay(LibraryImporterView(model: photos[0]), alignment: .center)
}
