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
    case file, url, library, camera, playground
    
    var systemImage: String {
        switch self {
        case .file:
            return "folder"
        case .url:
            return "link.badge.plus"
        case .library:
            return "photo.stack"
        case .camera:
            return "camera"
        case .playground:
            return "apple.image.playground"
        }
    }
    
    var localizedLabel: String {
        switch self {
        case .file:
            String(localized: "File", bundle: .module)
        case .url:
            String(localized: "URL", bundle: .module)
        case .library:
            String(localized: "Photo Library", bundle: .module)
        case .camera:
            String(localized: "Camera", bundle: .module)
        case .playground:
            String(localized: "Image Playground", bundle: .module)
        }
    }
    
    var duration: CGFloat {
        switch self {
        case .file:
            return 0.3
        case .url:
            return 0.35
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
        case .url:
            return offset(atIndex: 1, layoutDown: layoutDown)
        case .library:
            return offset(atIndex: 2, layoutDown: layoutDown)
        case .camera:
            return offset(atIndex: 3, layoutDown: layoutDown)
        case .playground:
            return offset(atIndex: 4, layoutDown: layoutDown)
        }
    }
    
    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 120
        let startAngleDeg = -180.0
        let step = 90.0 / Double(5 - 1)
        
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
    @State private var showRemoteURLImporter = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showImagePlayground = false
    
    var body: some View {
#if os(visionOS)
        InlineImporterContentView(
            itemId: itemId,
            layoutDown: layoutDown,
            isExpanded: $isExpanded,
            showImporter: $showImporter,
            showRemoteURLImporter: $showRemoteURLImporter,
            showCamera: $showCamera,
            showLibrary: $showLibrary,
            showImagePlayground: $showImagePlayground,
            selectedItem: $selectedItem
        )
#elseif os(tvOS)
        GlassEffectContainer {
            InlineImporterContentView(
                itemId: itemId,
                layoutDown: layoutDown,
                isExpanded: $isExpanded,
                showImporter: $showImporter,
                showRemoteURLImporter: $showRemoteURLImporter,
                showCamera: $showCamera,
                showLibrary: $showLibrary,
                showImagePlayground: $showImagePlayground
            )
        }
#else
        GlassEffectContainer {
            InlineImporterContentView(
                itemId: itemId,
                layoutDown: layoutDown,
                isExpanded: $isExpanded,
                showImporter: $showImporter,
                showRemoteURLImporter: $showRemoteURLImporter,
                showCamera: $showCamera,
                showLibrary: $showLibrary,
                showImagePlayground: $showImagePlayground,
                selectedItem: $selectedItem
            )
        }
#endif
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // `preopen`/`layoutDown` must be included: `.equatable()` (see ViewController.swift)
        // uses this to decide whether to skip re-rendering, and both drive stored state
        // (`isExpanded`'s seed, the button-fan's orientation) that must update when they
        // change for the same `itemId`. See CODE_AUDIT_9 §5.1.
        lhs.itemId == rhs.itemId && lhs.preopen == rhs.preopen && lhs.layoutDown == rhs.layoutDown
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` property on `InlineImporterView` itself.

private struct InlineImporterContentView: View {
    let itemId: UUID
    let layoutDown: Bool

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var isExpanded: Bool
    @Binding var showImporter: Bool
    @Binding var showRemoteURLImporter: Bool
    @Binding var showCamera: Bool
    @Binding var showLibrary: Bool
    @Binding var showImagePlayground: Bool
#if !os(tvOS)
    @Binding var selectedItem: PhotosPickerItem?
#endif

    var body: some View {
        ZStack {
            button(type: .file)
            button(type: .url)
            button(type: .library)
            button(type: .camera)
            button(type: .playground)

            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    isExpanded.toggle()
                }
            } label: {
                Label { Text(importerTitle) } icon: { Image(systemName: "photo.badge.plus") }
                .frame(width: 32, height: 32)
            }
            .selectedRoundButton(title: importerTitle, module: .space, isSelected: isExpanded)
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: root.config.fileTypes) { result in
            guard let url = try? result.get() else { return }
            Task {
                await root.editController.resetFile(url: url, itemId: itemId)
            }
        }
        .remoteFileURLImporter(
            isPresented: $showRemoteURLImporter,
            editControllable: root.editController,
            itemId: itemId
        )
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
#if os(macOS)
        // Mac has no camera/Photos-library picker sheet — instead, this whole importer accepts
        // an image dragged in from an external device (Image Capture, Photos, or a Finder
        // window backed by a camera/SD card/external drive). See CODE_AUDIT §4.2.
        .onDrop(of: ItemController.importImageTypes, isTargeted: nil) { providers in
            let id = itemId
            Task {
                guard let data = try? await ItemController.importImageFromProviders(providers) else { return }
                await update(id: id, image: AKImage(data: data))
            }
            return true
        }
#endif
    }

    private var importerTitle: String {
        String(localized: "Importer", bundle: .module)
    }

    private func update(id: UUID, image: AKImage?) async {
        await root.editController.resetPhoto(image: image, itemId: id)
    }

    private func button(type: PhotoImporterButtonType) -> some View {
        return Button {
            switch type {
            case .file:
                showImporter.toggle()
            case .url:
                showRemoteURLImporter.toggle()
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
            .frame(width: 32, height: 32)
            .opacity(isExpanded ? 1 : 0)
        }
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .selectedRoundButton(title: type.localizedLabel, module: .photo, isSelected: false)
        .offset(type.offset(expanded: isExpanded, layoutDown: layoutDown))
        .animation(
            reduceMotion ? nil : .spring(duration: type.duration * 3, bounce: 0.2),
            value: isExpanded
        )
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
