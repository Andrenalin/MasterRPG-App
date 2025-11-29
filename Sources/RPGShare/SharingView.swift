// @copyright André Trettin

import AndrenalinKit
import RolePlayGameKit
import SwiftUI
import UniformTypeIdentifiers
import os.log
import RegexBuilder

struct SharingView: View {
    @MainActor
    init(itemProviders: [NSItemProvider], extensionContext: NSExtensionContext? = nil) {
        self.itemProviders = itemProviders
        self.extensionContext = extensionContext
        self._appStore = State(wrappedValue: AppModel.shared)
        self._databaseModel = State(wrappedValue: DataBaseModel(useCloudKit: AppModel.shared.settingsModel.useCloudKit, currentActor: .sharingExtension))
    }
    
    // Entry State
    let itemProviders: [NSItemProvider]
    let extensionContext: NSExtensionContext?
    
    // Extension State
    @State private var appModel: AppModel
    @State private var databaseModel: DataBaseModel
    @State private var loaded = false

    // ViewModel
    @State private var imageListModel = ImageListModel()
    @State private var moduleChooserModel = ModuleChooserModel()
    @State private var inputModel = InputModel()
    
    var body: some View {
        GeometryReader {
            let size = $0.size
            ScrollView {
                VStack(spacing: 12) {
                    SharingHeader(cancelAction: close)

                    ModuleChooserView(model: moduleChooserModel)

                    PhotoSection(imageList: imageListModel, size: size)

                    SharingInput(model: inputModel)

                    SaveAction(appModel: appModel, inputModel: inputModel, imageListModel: imageListModel, moduleChooserModel: moduleChooserModel, closeAction: close)
                    
                    Spacer(minLength: /*@START_MENU_TOKEN@*/0/*@END_MENU_TOKEN@*/)
                }
                .animation(.bouncy, value: moduleChooserModel.showPhotoWarning)
                .animation(.bouncy, value: imageListModel.images)
            }
            .keyboardAvoiding()
            .padding()
            .task {
                await extractItems(size: size)
                databaseModel.setup()
            }
            .onChange(of: databaseModel.context, initial: true) {
                guard let context = databaseModel.context else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appModel.setupRootModels(context: context, spotlightIndexer: nil)
                }
            }
        }
    }
    
    @MainActor
    private func extractItems(size: CGSize) async {
        guard !loaded else { return }
        
        let items = itemProviders
        let importer = ItemProviderImporter()
        if let raw = try? await importer.loadImages(from: items) {
            imageListModel.images = raw
            moduleChooserModel.hasPhotos = !raw.isEmpty
        }

        if let raw = try? await importer.loadTexts(from: items) {
            let firstText = (raw.first ?? "").split(separator: .whitespace).first ?? ""
            inputModel.name = String(firstText)
            inputModel.text = raw.joined(separator: "\n")
        }
        loaded = true
    }
    
    private func close() {
        extensionContext?.completeRequest(returningItems: [])
    }
}
