// @copyright André Trettin

import CoreRPG
import SwiftUI

#if !os(tvOS)
@preconcurrency import PDFKit
#endif

struct PdfViewerView: View {
    init(model: PdfModel, entryId: UUID? = nil, withoutBookmark: Bool = false, dismissAction: (() -> Void)? = nil) {
        self.model = model
        self.entryId = entryId
        self.withoutBookmark = withoutBookmark
        self.dismissAction = dismissAction
    }
    
    let model: PdfModel
    let entryId: UUID?
    let withoutBookmark: Bool
    let dismissAction: (() -> Void)?
    
    @Environment(PdfRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showGame) private var showGame
    
    @State private var searchModel = PdfSearchModel()
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack {
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
#if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
            }
#endif
            .applyIf(!showGame) {
                $0.searchable(text: $searchModel.displaySearchText, placement: .automatic, prompt: Text("Find in pdf", bundle: .module))
            }
            .onSubmit(of: .search) {
                searchModel.resetSearch()
            }
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
            Task { @MainActor in
                let pdfTask = Task.detached {
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

private extension PdfViewerView {
    var entry: PdfEntryModel? {
        guard entryId == nil else { return nil }
        return PdfEntryModel.empty(UUID())
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
        
    PdfViewerView(model: PdfModel.preview)
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}

