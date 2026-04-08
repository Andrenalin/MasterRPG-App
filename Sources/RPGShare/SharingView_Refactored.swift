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
struct SharingView_Refactored: View {
    
    // MARK: - Properties
    
    let itemProviders: [NSItemProvider]
    let extensionContext: NSExtensionContext?
    
    // MARK: - State
    
    @State private var databaseService: ShareExtensionDatabaseService
    @State private var moduleFactory: ShareExtensionModuleFactory?
    
    @State private var imageListModel = ImageListModel()
    @State private var moduleChooserModel = ModuleChooserModel()
    @State private var inputModel = InputModel()
    
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // MARK: - Initialization
    
    @MainActor
    init(
        itemProviders: [NSItemProvider],
        extensionContext: NSExtensionContext? = nil,
        useCloudKit: Bool = AppModel.shared.settingsModel.useCloudKit
    ) {
        self.itemProviders = itemProviders
        self.extensionContext = extensionContext
        self._databaseService = State(wrappedValue: ShareExtensionDatabaseService(useCloudKit: useCloudKit))
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            if isLoading {
                loadingView
            } else if let errorMessage {
                errorView(message: errorMessage)
            } else {
                contentView(size: geometry.size)
            }
        }
        .task {
            await initialize()
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            
            Text("Error")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Close") {
                close()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func contentView(size: CGSize) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                SharingHeader(cancelAction: close)
                
                ModuleChooserView(model: moduleChooserModel)
                
                PhotoSection(imageList: imageListModel, size: size)
                
                SharingInput(model: inputModel)
                
                saveButton
                
                Spacer(minLength: 0)
            }
            .animation(.bouncy, value: moduleChooserModel.showPhotoWarning)
            .animation(.bouncy, value: imageListModel.images)
        }
        .keyboardAvoiding()
        .padding()
        .disabled(isSaving)
        .overlay {
            if isSaving {
                savingOverlay
            }
        }
    }
    
    private var saveButton: some View {
        Button {
            Task {
                await saveContent()
            }
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Save")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(inputModel.name.isEmpty)
    }
    
    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                Text("Saving...")
                    .foregroundStyle(.white)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Initialization
    
    @MainActor
    private func initialize() async {
        do {
            // 1. Extract content from item providers
            await extractItems()
            
            // 2. Determine which modules we need based on content
            let requiredModules = determineRequiredModules()
            
            // 3. Setup database with only required modules
            try await databaseService.setup(for: requiredModules)
            
            // 4. Create factory with context
            guard let context = databaseService.context else {
                throw ShareExtensionError.contextNotAvailable
            }
            
            moduleFactory = ShareExtensionModuleFactory(context: context)
            
            // 5. Ready to use
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
        
        // Load images
        if let images = try? await importer.loadImages(from: itemProviders) {
            imageListModel.images = images
            moduleChooserModel.hasPhotos = !images.isEmpty
        }
        
        // Load text
        if let texts = try? await importer.loadTexts(from: itemProviders) {
            let joined = texts.joined(separator: "\n")
            let firstWord = joined.components(separatedBy: CharacterSet.whitespacesAndNewlines).first ?? ""
            inputModel.name = firstWord
            inputModel.text = joined
        }
    }
    
    private func determineRequiredModules() -> [NetworkModules] {
        var modules: [NetworkModules] = []
        
        // Always include the selected module
        modules.append(moduleChooserModel.currentModule)
        
        // Add modules based on content
        if !imageListModel.images.isEmpty {
            modules.append(.photo)
        }
        
        let text = inputModel.text
        if !text.isEmpty {
            modules.append(.adventure)
        }
        
        // Remove duplicates
        return Array(Set(modules))
    }
    
    // MARK: - Save Action
    
    @MainActor
    private func saveContent() async {
        guard let factory = moduleFactory else { return }
        let selectedModule = moduleChooserModel.currentModule
        
        isSaving = true
        
        do {
            // Prepare content
            let content = ShareContent(
                text: inputModel.text,
                images: imageListModel.images.compactMap { $0.imageData },
                data: nil
            )
            
            // Create item
            let itemId = try await factory.createItem(
                in: selectedModule,
                name: inputModel.name,
                content: content
            )
            
            // Save to Core Data
            try await databaseService.save()
            
            os.Logger.bootStrap.info("Successfully saved item \(itemId) to \(selectedModule.rawValue)")
            
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
