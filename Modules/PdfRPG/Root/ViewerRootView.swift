// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
@preconcurrency import PDFKit
#endif
import SwiftUI


struct ViewerRootView: View {
    let model: PdfModel
    var entryId: UUID? = nil
    let configuration: ViewerConfiguration
    var onTextExtracted: ((String) -> Void)? = nil
    var dismissAction: (() -> Void)? = nil

    @Environment(PdfRootModel.self) private var root

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchModel = PdfSearchModel()

    init(model: PdfModel, entryId: UUID? = nil, configuration: ViewerConfiguration, onTextExtracted: ((String) -> Void)? = nil, dismissAction: (() -> Void)? = nil) {
        self.model = model
        self.entryId = entryId
        self.configuration = configuration
        self.onTextExtracted = onTextExtracted
        self.dismissAction = dismissAction
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
                            .scaleEffect(1.5)
                            .foregroundStyle(Color.accentColor)
                    }
                }
#endif
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .overlay(alignment: .topTrailing) {
            GlassEffectContainerView {
                SelectionBar(editController: root.editController, model: model, searchModel: searchModel, withoutBookmark: !configuration.canBookmark)
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
            ToolbarItem(placement: .automatic) {
                extractionButton
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
        .applyIf(configuration.aiExtractor == false) {
            $0.navigationTitle(Text(verbatim: model.name))
                .navigationBarTitleDisplayModeAll(.inline)
        }
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
                withAnimation(reduceMotion ? nil : .default) {
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
            Label {
                Text("Close PDF", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .labelStyle(.iconOnly)
        }
#if os(macOS)
                .foregroundStyle(root.config.module.tint)
#else
                .tint(root.config.module.tint)
#endif
    }

#if !os(tvOS)
    var extractionButton: some View {
        Button {
            navigator.navigate(to: PdfDetailRoute.pdfBlockExtraction(model.id), method: .managedSheet)
        } label: {
            Label {
                Text("Extract with AI", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
#if os(macOS)
                .foregroundStyle(root.config.module.tint)
#else
                .tint(root.config.module.tint)
#endif
    }
#endif
    
}

#Preview(traits: .mockData) {
    
    ManagedNavigationStack {
        ViewerRootView(model: PdfModel.preview, configuration: ViewerConfiguration())
    }
#if os(macOS)
    .frame(width: 800, height: 600)
#endif
}
