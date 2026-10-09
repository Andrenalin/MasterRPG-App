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

struct InlineImporterView: View, Equatable {
    init(itemId: UUID, preopen: Bool, layoutDown: Bool) {
        self.itemId = itemId
        self.preopen = preopen
        self.layoutDown = layoutDown
    }

    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool

    var body: some View {
#if os(visionOS)
        InlineImporterContentView(itemId: itemId, preopen: preopen, layoutDown: layoutDown)
#else
        GlassEffectContainer {
            InlineImporterContentView(itemId: itemId, preopen: preopen, layoutDown: layoutDown)
        }
#endif
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // `preopen`/`layoutDown` must be included: `.equatable()` (see ViewController.swift)
        // uses this to decide whether to skip re-rendering, and both drive the fan (its
        // initial state and orientation). See CODE_AUDIT_9 §5.1.
        lhs.itemId == rhs.itemId && lhs.preopen == rhs.preopen && lhs.layoutDown == rhs.layoutDown
    }
}

private struct InlineImporterContentView: View {
    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool

    @Environment(PhotoRootModel.self) private var root
#if !os(tvOS)
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var selectedItem: PhotosPickerItem?
#endif

    @State private var showImporter = false
    @State private var showRemoteUrlImporter = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showImagePlayground = false
    @State private var importErrorMessage: String?
    @State private var replacementConfirmation = FileReplacementConfirmation()

    var body: some View {
        ImporterFanView(
            title: String(localized: "Importer", bundle: .module),
            systemImage: "photo.badge.plus",
            module: .photo,
            preopen: preopen,
            layoutDown: layoutDown,
            items: fanItems
        )
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: root.config.fileTypes) { result in
            switch result {
            case .success(let url):
                Task {
                    await replacementConfirmation.resetFile(url: url, itemId: itemId, editControllable: root.editController)
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .remoteFileURLImporter(
            isPresented: $showRemoteUrlImporter,
            editControllable: root.editController,
            itemId: itemId,
            replacementConfirmation: replacementConfirmation
        )
        .imagePlaygroundSheet(
            isPresented: $showImagePlayground,
            concept: String(localized: "Create a portrait of a fantasy character", bundle: .module)
        ) { url in
            Task {
                await replacementConfirmation.resetFile(url: url, itemId: itemId, editControllable: root.editController)
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $selectedItem, matching: .images, photoLibrary: .shared())
        .onChange(of: selectedItem) {
            guard let localItem = selectedItem else { return }
            // Cleared at once: the selection stayed, so picking the same library photo again
            // was no change and did nothing. See CODE_AUDIT_21 §5.28.
            selectedItem = nil
            let id = itemId
            Task {
                do {
                    guard let data = try await localItem.loadTransferable(type: Data.self) else {
                        importErrorMessage = String(localized: "The selected photo could not be loaded.", bundle: .module)
                        return
                    }
                    guard let replaced = await replacementConfirmation.disposal(forReplacingFileOf: id, editControllable: root.editController) else { return }
                    guard try await root.editController.resetPhoto(data: data, itemId: id, replaced: replaced) else {
                        importErrorMessage = String(localized: "The selected photo could not be loaded.", bundle: .module)
                        return
                    }
                } catch {
                    importErrorMessage = error.localizedDescription
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
                do {
                    guard let data = try await ItemController.importImageFromProviders(providers) else { return }
                    guard let replaced = await replacementConfirmation.disposal(forReplacingFileOf: id, editControllable: root.editController) else { return }
                    guard try await root.editController.resetPhoto(data: data, itemId: id, replaced: replaced) else {
                        importErrorMessage = String(localized: "The dropped image could not be loaded.", bundle: .module)
                        return
                    }
                } catch {
                    importErrorMessage = error.localizedDescription
                }
            }
            return true
        }
#endif
        .importFailureAlert(message: $importErrorMessage)
        .fileReplacementAlert(replacementConfirmation)
    }

    /// Only the importers this device can use: the camera sheet exists on iOS only, and Image
    /// Playground only where the system supports it. See CODE_AUDIT_Folder §9.6.
    private var fanItems: [ImporterFanItem] {
        var types: [PhotoImporterButtonType] = []
#if !os(tvOS)
        types += [.file, .url, .library]
#endif
#if os(iOS)
        types.append(.camera)
#endif
#if !os(tvOS)
        if supportsImagePlayground {
            types.append(.playground)
        }
#endif
        return types.map { type in
            ImporterFanItem(id: type.rawValue, title: type.localizedLabel, systemImage: type.systemImage) {
                show(type)
            }
        }
    }

    private func show(_ type: PhotoImporterButtonType) {
        switch type {
        case .file: showImporter.toggle()
        case .url: showRemoteUrlImporter.toggle()
        case .library: showLibrary.toggle()
        case .camera: showCamera.toggle()
        case .playground: showImagePlayground.toggle()
        }
    }

    private func update(id: UUID, image: AKImage?) async {
        guard let replaced = await replacementConfirmation.disposal(forReplacingFileOf: id, editControllable: root.editController) else { return }
        do {
            try await root.editController.resetPhoto(image: image, itemId: id, replaced: replaced)
        } catch {
            importErrorMessage = error.localizedDescription
        }
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
