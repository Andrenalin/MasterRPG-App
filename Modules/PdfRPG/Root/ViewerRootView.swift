// @copyright André Trettin

import CoreRPG
import SwiftUI

#if !os(tvOS)
@preconcurrency import PDFKit
#endif

struct ViewerRootView: View {
    let model: PdfModel
    var entryId: UUID? = nil
    var windowMode: Bool = false
    var withoutBookmark: Bool = false
    var dismissAction: (() -> Void)? = nil
    
    @Environment(PdfRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showGame) private var showGame
    @Environment(\.appSizeMode) private var appSizeMode
    
    @State private var searchModel = PdfSearchModel()
    
    var body: some View {
        let _ = Self._printChanges()
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
                if shouldShowCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        closeButton
                    }
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
    var shouldShowCloseButton: Bool {
        valueFor(iOS: appSizeMode == .compact || dismissAction != nil, macOS: false, tvOS: dismissAction != nil, visionOS: dismissAction != nil)
    }

    var searchBar: Bool {
        valueFor(iOS: !showGame, macOS: windowMode, tvOS: !showGame, visionOS: !showGame)
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
        .opacity(showGame ? 0 : 1)
    }

}

#Preview(traits: .mockData) {
    
    ManagedNavigationStack {
        ViewerRootView(model: PdfModel.preview)
    }
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}

