// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import SwiftUI
import UniformTypeIdentifiers
import Foundation
import os.log

extension Logger {
    static let bootStrap = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RPGShare", category: "ShareExtension")
}

/// Refactored SharingView with proper architecture
/// - Uses lightweight database service
/// - Proper Swift concurrency
/// - Clear separation of concerns
/// - Efficient module loading
struct SharingView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    // MARK: - Properties
    
    let itemProviders: [NSItemProvider]
    let extensionContext: NSExtensionContext?
    
    // MARK: - State
    
    @State private var databaseService: ShareExtensionDatabaseService
    @State private var saveController: ShareExtensionSaveController?
    
    @State private var imageListModel = ImageListModel()
    @State private var moduleChooserModel = ModuleChooserModel()
    @State private var inputModel = InputModel()
    
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Shared items that could not be read; shown above the content.
    @State private var skippedItemCount = 0
    @State private var containerSize: CGSize = .zero

    private let performsInitialization: Bool
    
    // MARK: - Initialization
    
    @MainActor
    init(
        itemProviders: [NSItemProvider],
        extensionContext: NSExtensionContext? = nil,
        useCloudKit: Bool = AppSettingsModel.readUseCloudKitFromDefaults(),
        previewContent: (name: String, text: String, module: NetworkModules)? = nil
    ) {
        self.itemProviders = itemProviders
        self.extensionContext = extensionContext
        self._databaseService = State(wrappedValue: ShareExtensionDatabaseService(useCloudKit: useCloudKit))
        self.performsInitialization = previewContent == nil

        if let previewContent {
            let inputModel = InputModel()
            inputModel.name = previewContent.name
            inputModel.text = previewContent.text
            _inputModel = State(initialValue: inputModel)

            let moduleChooserModel = ModuleChooserModel()
            moduleChooserModel.currentModule = previewContent.module
            _moduleChooserModel = State(initialValue: moduleChooserModel)
            _isLoading = State(initialValue: false)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if isLoading {
                SharingLoadingView()
            } else if let errorMessage {
                errorView(message: errorMessage)
            } else {
                contentView(size: containerSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            containerSize = newValue
        }
        .task {
            guard performsInitialization else { return }
            await initialize()
        }
    }
    
    // MARK: - Views

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            
            Text("Error", bundle: .main)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            
            Text(verbatim: message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                close()
            } label: {
                Text("Close", bundle: .main)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func contentView(size: CGSize) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                SharingHeader(cancelAction: close)

                if skippedItemCount > 0 {
                    Label {
                        Text("\(skippedItemCount) shared items could not be read and were left out.", bundle: .main)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                    .font(.footnote)
                }

                ModuleChooserView(model: moduleChooserModel)
                
                PhotoSection(imageList: imageListModel, size: size)
                
                SharingInput(model: inputModel)

                SharingSaveButtonView(
                    inputModel: inputModel,
                    canSave: ShareExtensionError.canSave(
                        to: moduleChooserModel.currentModule,
                        imageCount: imageListModel.images.count
                    ),
                    saveContent: saveContent
                )

                Spacer(minLength: 0)
            }
            .animation(reduceMotion ? nil : .bouncy, value: moduleChooserModel.showPhotoWarning)
            .animation(reduceMotion ? nil : .bouncy, value: imageListModel.images)
        }
        .keyboardAvoiding()
        .padding()
        .disabled(isSaving)
        .accessibilityHidden(isSaving)
        .overlay {
            if isSaving {
                SharingSavingOverlayView()
            }
        }
    }

    // MARK: - Initialization
    
    @MainActor
    private func initialize() async {
        do {
            // 1. Extract content from item providers
            await extractItems()
            
            // 2. Setup database with ALL modules (required for proper Core Data integrity)
            try await databaseService.setup()
                        
            saveController = ShareExtensionSaveController(
                databaseService: databaseService
            )
            
            // 4. Ready to use
            isLoading = false
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            os.Logger.bootStrap.error("Failed to initialize share extension: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func extractItems() async {
        let importer = ItemProviderImporter()
        var skipped = 0

        // Load images
        if let images = try? await importer.loadImages(from: itemProviders) {
            imageListModel.images = images.values
            moduleChooserModel.hasPhotos = !images.values.isEmpty
            skipped += images.skippedCount
        }

        // Load text
        var hasText = false
        if let texts = try? await importer.loadTexts(from: itemProviders) {
            hasText = !texts.values.isEmpty
            skipped += texts.skippedCount
            if hasText {
                let joined = texts.values.joined(separator: "\n")
                let firstWord = joined.components(separatedBy: CharacterSet.whitespacesAndNewlines).first ?? ""
                inputModel.name = firstWord
                inputModel.text = joined
            }
        }

        skippedItemCount = skipped
        // Nothing could be read at all: say so instead of showing an empty form.
        if imageListModel.images.isEmpty, !hasText {
            errorMessage = String(localized: "The shared items could not be read.", bundle: .main)
        }
    }

    // MARK: - Save Action
    
    @MainActor
    private func saveContent() async {
        guard let controller = saveController else { return }
        let selectedModule = moduleChooserModel.currentModule
        
        isSaving = true
        
        do {
            // Save using lightweight data controllers
            try await controller.saveContent(
                to: selectedModule,
                name: inputModel.name,
                text: inputModel.text,
                images: imageListModel.images
            )
            
            os.Logger.bootStrap.info("Successfully saved to \(selectedModule.rawValue)")
            
            // Close extension
            close()
            
        } catch {
            os.Logger.bootStrap.error("Failed to save content: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
    
    // MARK: - Actions
    
    private func close() {
        extensionContext?.completeRequest(returningItems: [])
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct SharingLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityLabel(Text("Loading…", bundle: .main))
            Text("Loading…", bundle: .main)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SharingSaveButtonView: View {
    let inputModel: InputModel
    /// `false` when the chosen module has nothing to save, such as Photo with no image.
    let canSave: Bool
    let saveContent: () async -> Void

    var body: some View {
        Button {
            Task {
                await saveContent()
            }
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Save", bundle: .main)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(inputModel.name.isEmpty || !canSave)
    }
}

private struct SharingSavingOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                ProgressView()
                    .accessibilityLabel(Text("Saving…", bundle: .main))
                Text("Saving…", bundle: .main)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .padding()
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        }
    }
}

#Preview("Share an adventure") {
    SharingView(
        itemProviders: [],
        useCloudKit: false,
        previewContent: (
            name: "The Verdant Vault",
            text: "A moss-covered stair descends beneath the ruined observatory.",
            module: .adventure
        )
    )
}
