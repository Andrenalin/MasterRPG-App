// @copyright André Trettin

import CoreRPG
import GeneratorRPG
import SwiftUI

#if !os(tvOS)
@preconcurrency import PDFKit
#endif

struct ViewerRootView: View {
    let model: PdfModel
    var entryId: UUID? = nil
    let configuration: ViewerConfiguration
    var withoutBookmark: Bool = false
    var onTextExtracted: ((String) -> Void)? = nil
    var dismissAction: (() -> Void)? = nil

    @Environment(PdfRootModel.self) private var root

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var searchModel = PdfSearchModel()
    @State private var blockExtractor = PdfBlockExtractorController()

    init(model: PdfModel, entryId: UUID? = nil, configuration: ViewerConfiguration, withoutBookmark: Bool = false, onTextExtracted: ((String) -> Void)? = nil, dismissAction: (() -> Void)? = nil) {
        self.model = model
        self.entryId = entryId
        self.configuration = configuration
        self.withoutBookmark = withoutBookmark
        self.onTextExtracted = onTextExtracted
        self.dismissAction = dismissAction

        // Set up the callback
        _blockExtractor = State(initialValue: {
            let controller = PdfBlockExtractorController()
            controller.onTextExtracted = onTextExtracted
            return controller
        }())
    }
    
    var body: some View {
        VStack {
#if !os(tvOS)
            PdfContentView(searchModel: searchModel, horizontal: false, entry: entry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(searchModel.pdfId)
                .overlay {
                    if searchModel.isSearching {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.large)
                            .foregroundStyle(Color.accentColor)
                    }
                }
#endif
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .overlay(alignment: .topTrailing) {
            GlassEffectContainerView {
                SelectionBar(editController: root.editController, model: model, searchModel: searchModel, withoutBookmark: withoutBookmark)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            GlassEffectContainerView {
                SearchBar(searchModel: searchModel)
            }
        }
        .toolbar {
            if configuration.closeButton {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
            }

#if !os(tvOS)
            if configuration.addToolbar && blockExtractor.isModelAvailable {
                ToolbarItem(placement: .primaryAction) {
                    extractionButton
                }
            }
#endif
        }
        .applyIf(searchBar) {
            $0.searchable(text: $searchModel.displaySearchText, placement: .automatic, prompt: Text("Find in pdf", bundle: .module))
        }
        .onSubmit(of: .search) {
            searchModel.resetSearch()
        }
#if !os(visionOS)
        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
        .navigationTitle(Text(model.name))
#if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onChange(of: model, initial: true) {
            let id = model.id
            guard model.url != nil else {
                searchModel.pdfId = model.id
                return
            }
#if !os(tvOS)
            Task {
                let pdfTask = Task {
                    await root.itemController.pdfDocument(for: id)
                }
                let doc = await pdfTask.value
                searchModel.pdfDoc = doc
                withAnimation {
                    searchModel.pdfId = id
                }
            }
#endif
        }
    }
}

private extension ViewerRootView {
    var searchBar: Bool {
        valueFor(iOS: !configuration.isGame, macOS: configuration.addToolbar, tvOS: !configuration.isGame, visionOS: !configuration.isGame)
    }
    
    var entry: PdfEntryModel? {
        guard let entryId else { return nil }
        return model[entryId]
    }
    
    var closeButton: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark.circle")
        }
        .foregroundStyle(root.config.module.tint)
    }

    var extractionButton: some View {
        Button {
            Task {
                await extractBlocks()
            }
        } label: {
            Label {
                Text("Extract with AI", bundle: .module)
            } icon: {
                if blockExtractor.isExtracting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                }
            }
        }
        .disabled(blockExtractor.isExtracting)
        .foregroundStyle(root.config.module.tint)
    }

    func extractBlocks() async {
        guard let pdfDocument = searchModel.pdfDoc else {
            return
        }

        _ = await blockExtractor.extractWithProgress(from: pdfDocument)
    }

}

#Preview(traits: .mockData) {
    
    ManagedNavigationStack {
        ViewerRootView(model: PdfModel.preview, configuration: ViewerConfiguration())
    }
#if os(macOS)
    .frame(width: 800, height: 600)
#endif
}

