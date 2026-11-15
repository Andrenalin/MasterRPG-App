// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
import PDFKit
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
                .id(PdfViewerLoadKey(id: searchModel.pdfId, version: searchModel.pdfVersion))
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
        .applyIf(toolbar) {
            $0.toolbar {
                if configuration.closeButton {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButtonView(dismissAction: dismissAction)
                    }
                }

#if !os(tvOS)
                ToolbarItem(placement: .automatic) {
                    ExtractionButtonView(model: model)
                }
#endif
            }
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
        // `.task(id:)` instead of `.onChange` + a manually-spawned `Task`: it cancels the
        // in-flight PDF decode automatically if `model` changes again or the view goes
        // away, rather than leaving an orphaned Task decoding in the background.
        // See CODE_AUDIT_Pdf §3.4.
        // Keyed on the file version, not the (in-place mutated) model reference: a replaced file
        // reloads. See CODE_AUDIT_26 §5.38.
        .task(id: PdfViewerLoadKey(id: model.id, version: model.version)) {
            let id = model.id
            let version = model.version
            guard model.url != nil else {
#if !os(tvOS)
                searchModel.pdfDoc = nil
                searchModel.pdfUnavailable = false
#endif
                searchModel.pdfId = model.id
                searchModel.pdfVersion = version
                return
            }
#if !os(tvOS)
            searchModel.pdfUnavailable = false
            let doc = await root.itemController.pdfDocument(for: id)
            guard !Task.isCancelled else { return }
            searchModel.pdfDoc = doc
            searchModel.pdfUnavailable = doc == nil
            withAnimation(reduceMotion ? nil : .default) {
                searchModel.pdfId = id
                searchModel.pdfVersion = version
            }
#endif
        }
    }
}

private extension ViewerRootView {
    /// On macOS the game screen shares one window toolbar with the game's own search field,
    /// so a shared pdf must not add toolbar items or a second `.searchable` to it
    /// (NSToolbar raises on a duplicate `com.apple.SwiftUI.search` item).
    var toolbar: Bool {
        valueFor(iOS: true, macOS: !configuration.isGame, tvOS: true, visionOS: true)
    }

    var searchBar: Bool {
        valueFor(iOS: !configuration.isGame, macOS: configuration.addToolbar && !configuration.isGame, tvOS: !configuration.isGame, visionOS: !configuration.isGame)
    }
    
    var entry: PdfEntryModel? {
        guard let entryId else { return nil }
        return model[entryId]
    }
    
}

private struct CloseButtonView: View {
    let dismissAction: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(PdfRootModel.self) private var root

    var body: some View {
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
                .moduleForegroundStyle(root.config.module)
#else
                .moduleTint(root.config.module)
#endif
    }
}

#if !os(tvOS)
private struct ExtractionButtonView: View {
    let model: PdfModel

    @Environment(\.navigator) private var navigator
    @Environment(PdfRootModel.self) private var root

    var body: some View {
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
                .moduleForegroundStyle(root.config.module)
#else
                .moduleTint(root.config.module)
#endif
    }
}
#endif

#Preview(traits: .mockData) {
    
    ManagedNavigationStack {
        ViewerRootView(model: PdfModel.preview, configuration: ViewerConfiguration())
    }
#if os(macOS)
    .frame(width: 800, height: 600)
#endif
}
