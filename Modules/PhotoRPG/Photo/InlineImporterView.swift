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
    
    var localizedLabel: LocalizedStringResource {
        switch self {
        case .file:
            LocalizedStringResource("File", bundle: .module)
        case .library:
            LocalizedStringResource("Photo Library", bundle: .module)
        case .camera:
            LocalizedStringResource("Camera", bundle: .module)
        case .playground:
            LocalizedStringResource("Image Playground", bundle: .module)
        }
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

struct InlineImporterView: View, Equatable {
    init(itemId: UUID, preopen: Bool, layoutDown: Bool) {
        self.itemId = itemId
        self.preopen = preopen
        self.layoutDown = layoutDown
        self._isExpanded = State(wrappedValue: preopen)
    }
    
    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                withAnimation(reduceMotion ? nil : .default) {
                    isExpanded.toggle()
                }
            } label: {
                Label { Text("Importer", bundle: .module) } icon: { Image(systemName: "photo.badge.plus") }
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
            Task {
                await root.editController.resetFile(url: url, itemId: itemId)
            }
        }
        .imagePlaygroundSheet(
            isPresented: $showImagePlayground,
            concept: String(localized: "Create a portrait of a fantasy character", bundle: .module)
        ) { url in
            Task {
                await root.editController.resetFile(url: url, itemId: itemId)
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $selectedItem, matching: .images, photoLibrary: .shared())
        .onChange(of: selectedItem) {
            guard let localItem = selectedItem else { return }
            let id = itemId
            Task {
                if let data = try? await localItem.loadTransferable(type: Data.self) {
                    await update(id: id, image: AKImage(data: data))
                }
            }
        }
#endif
#if os(iOS)
        .sheet(isPresented: $showCamera) {
            ManagedPresentationView {
                CaptureImagePicker(shown: $showCamera) { [id = itemId] image in
                    await update(id: id, image: image)
                }
            }
        }
#endif
    }
    
    private func update(id: UUID, image: AKImage?) async {
        await root.editController.resetPhoto(image: image, itemId: id)
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
            Label {
                Text(type.localizedLabel)
            } icon: {
                Image(systemName: type.systemImage)
            }
                .labelStyle(.iconOnly)
                .frame(width: 50, height: 50)
                .opacity(isExpanded ? 1 : 0)
        }
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .borderLessTVBottonStyle()
#if !os(visionOS)
        .glassEffect(.regular.tint(.white.opacity(0.5)).interactive())
        .glassEffectID(type.rawValue, in: glassNamespace)
#endif
        .offset(type.offset(expanded: isExpanded, layoutDown: layoutDown))
        .animation(
            reduceMotion ? nil : .spring(duration: type.duration * 3, bounce: 0.2),
            value: isExpanded
        )
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    ZStack {
        Color
            .blue
        
        InlineImporterView(itemId: root.itemController.itemDataModel.items[0], preopen: true, layoutDown: true)
    }
}
