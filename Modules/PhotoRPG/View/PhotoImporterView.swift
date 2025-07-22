// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

#if canImport(ImagePlayground)
import ImagePlayground
#endif

struct PhotoImporterView: View {
    let model: PhotoDataModel
    let prominent: Bool

    var body: some View {
        contentView
//        ViewThatFits {
//            HStack(spacing: 40) {
//                contentView
//            }
//
//            VStack(spacing: 40) {
//                contentView
//            }
//        }
    }
    
    @ViewBuilder
    var contentView: some View {
        if #available(iOS 18.1, visionOS 2.4, macOS 15.1, *) {
            ImagePlaygroundImportView(model: model, prominent: prominent)
        }

        CameraImporterView(model: model, prominent: prominent)
        FileImporterView(model: model, prominent: prominent)
#if !os(tvOS)
        LibraryImporterView(model: model, prominent: prominent)
#endif
    }
}

@available(iOS 18.1, visionOS 2.4, macOS 15.1, *)
struct ImagePlaygroundImportView: View {
    let model: PhotoDataModel
    let prominent: Bool

    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Environment(PhotoRootModel.self) private var root
    @State private var showImagePlayground = false

    var body: some View {
        if supportsImagePlayground {
            GlassButton(isProminent: prominent) {
                showImagePlayground.toggle()
            } label: {
                Image(systemName: "apple.image.playground")
                    .imageScale(prominent ? .large : .medium)
            }
            .imagePlaygroundSheet(isPresented: $showImagePlayground, concept: "Create a protrait of a fanatsy character") { url in
                root.editController.resetPhoto(url: url, in: model)
            }
        }
    }
}

struct CameraImporterView: View {
    init(model: PhotoDataModel, prominent: Bool) {
        self.model = model
        self.prominent = prominent
        self.modelActor = model.modelActor()
    }

    let model: PhotoDataModel
    let prominent: Bool
    let modelActor: DataModelActor?

    @Environment(PhotoRootModel.self) private var root
    
    @State private var showCamera = false
    
    var body: some View {
#if os(iOS)
        if CaptureImagePicker.isCameraAvailable {
            GlassButton(isProminent: prominent) {
                showCamera.toggle()
            } label: {
                Image(systemName: "camera\(showCamera ? ".fill" : "")")
                    .imageScale(prominent ? .large : .medium)
            }
            .contentTransition(.symbolEffect(.replace.wholeSymbol))

            .sheet(isPresented: $showCamera) {
                CaptureImagePicker(shown: $showCamera) { [id = model.id] image in
                    await update(id: id, image: image)
                }
            }
        }
#endif
    }
    
    private func update(id: UUID, image: AKImage?) async {
        guard let modelActor else { return }
        await root.editController.resetPhoto(image: image, id: id, actor: modelActor)
    }
}

struct FileImporterView: View {
    let model: PhotoDataModel
    let prominent: Bool

    @Environment(PhotoRootModel.self) private var root
    @State private var showImporter = false
    
    var body: some View {
#if !os(tvOS)
        GlassButton(isProminent: prominent) {
            showImporter.toggle()
        } label: {
            Image(systemName: "folder\(showImporter ? ".fill" : "")")
                .imageScale(prominent ? .large : .medium)
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            root.editController.resetPhoto(url: url, in: model)
        }
#endif
    }
}

#if !os(tvOS)
struct LibraryImporterView: View {
    init(model: PhotoDataModel, prominent: Bool) {
        self.model = model
        self.prominent = prominent
        self.modelActor = model.modelActor()
    }

    let model: PhotoDataModel
    let prominent: Bool
    let modelActor: DataModelActor?

    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        LibraryPhotoPicker(prominent: prominent) { [id = model.id] image in
            await update(id: id, image: image)
        }
    }
    
    private func update(id: UUID, image: AKImage?) async {
        guard let modelActor else { return }
        await root.editController.resetPhoto(image: image, id: id, actor: modelActor)
    }
}
#endif


#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    VStack {
        Color
            .teal
            .frame(width: 256, height: 256)
            .overlay(CameraImporterView(model: models[0], prominent: false), alignment: .bottom)
            .overlay(FileImporterView(model: models[0], prominent: false), alignment: .top)
#if !os(tvOS)
            .overlay(LibraryImporterView(model: models[0], prominent: false), alignment: .center)
#endif

        PhotoImporterView(model: models[0], prominent: true)
    }
}
