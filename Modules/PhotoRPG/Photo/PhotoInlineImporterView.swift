// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import PhotosUI
#endif
import SwiftUI
import UniformTypeIdentifiers

#if canImport(ImagePlayground)
import ImagePlayground
#endif


enum PhotoImporterButtonType: String {
    case file, library, camera, playground
    
    var systemImage: String {
        switch self {
        case .file:
            return "folder"
        case .library:
            return "photo.stack"
        case .camera:
            return "camera"
        case .playground:
            return "apple.image.playground"
        }
    }
    
    var label: String {
        self.rawValue.capitalized
    }
    
    var duration: CGFloat {
        switch self {
        case .file:
            return 0.3
        case .library:
            return 0.4
        case .camera:
            return 0.5
        case .playground:
            return 0.6
        }
    }
    
    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else {
            return .zero
        }
        
        switch self {
        case .file:
            return offset(atIndex: 0, layoutDown: layoutDown)
        case .library:
            return offset(atIndex: 1, layoutDown: layoutDown)
        case .camera:
            return offset(atIndex: 2, layoutDown: layoutDown)
        case .playground:
            return offset(atIndex: 3, layoutDown: layoutDown)
        }
    }
    
    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 120
        let startAngleDeg = -180.0
        let step = 90.0 / Double(4 - 1)
        
        let angleDeg = startAngleDeg + (Double(index) * step)
        let angleRad = angleDeg * .pi / 180
        
        let x = cos(angleRad) * radius
        let y = sin(angleRad) * radius * (layoutDown ? -1 : 1)
        
        return CGSize(width: x, height: y)
    }
}

struct PhotoInlineImporterView: View {
    internal init(itemId: UUID, preopen: Bool, layoutDown: Bool) {
        self.itemId = itemId
        self.preopen = preopen
        self.layoutDown = layoutDown
        self._isExpanded = State(wrappedValue: preopen)
    }
    
    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool
    
    @Environment(PhotoRootModel.self) private var root
#if !os(tvOS)
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: Image? = nil
#endif
    
    @Namespace var glassNamespace
    
    @State private var isExpanded: Bool
    
    @State private var showImporter = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showImagePlayground = false
    
    var body: some View {
#if os(visionOS)
        content
#else
        GlassEffectContainer {
            content
        }
#endif
    }
    
    var content: some View {
        ZStack {
            button(type: .file)
            button(type: .library)
            button(type: .camera)
            button(type: .playground)
            
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                Label("Importer", systemImage: "photo.badge.plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 50, height: 50)
            }
            .borderLessTVBottonStyle()
#if !os(visionOS)
            .glassEffect(.regular.tint(.white.opacity(0.5)).interactive())
            .glassEffectID("menu", in: glassNamespace)
#endif
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: root.config.fileTypes) { result in
            guard let url = try? result.get() else { return }
            root.editController.resetPhoto(url: url)
        }
        .imagePlaygroundSheet(isPresented: $showImagePlayground, concept: "Create a protrait of a fanatsy character") { url in
            root.editController.resetPhoto(url: url)
        }
        .photosPicker(isPresented: $showLibrary, selection: $selectedItem, matching: .images, photoLibrary: .shared())
        .onChange(of: selectedItem) {
            guard let localItem = selectedItem else { return }
            let id = itemId
            Task.detached {
                if let data = try? await localItem.loadTransferable(type: Data.self) {
                    await update(id: id, image: AKImage(data: data))
                }
            }
        }
#endif
#if os(iOS)
        .sheet(isPresented: $showCamera) {
            CaptureImagePicker(shown: $showCamera) { [id = itemId] image in
                await update(id: id, image: image)
            }
        }
#endif
    }
    
    private func update(id: UUID, image: AKImage?) async {
        await root.editController.resetPhoto(image: image)
    }
    
    private func button(type: PhotoImporterButtonType) -> some View {
        return Button {
            switch type {
            case .file:
                showImporter.toggle()
            case .library:
                showLibrary.toggle()
            case .camera:
                showCamera.toggle()
            case .playground:
                showImagePlayground.toggle()
            }
        } label: {
            Label(type.label, systemImage: type.systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 50, height: 50)
                .opacity(isExpanded ? 1 : 0)
        }
        .borderLessTVBottonStyle()
#if !os(visionOS)
        .glassEffect(.regular.tint(.white.opacity(0.5)).interactive())
        .glassEffectID(type.label, in: glassNamespace)
#endif
        .offset(type.offset(expanded: isExpanded, layoutDown: layoutDown))
        .animation(.spring(duration: type.duration * 3, bounce: 0.2), value: isExpanded)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    ZStack {
        Color
            .blue
        
        PhotoInlineImporterView(itemId: root.itemController.itemDataModel.items[0], preopen: true, layoutDown: true)
    }
}
