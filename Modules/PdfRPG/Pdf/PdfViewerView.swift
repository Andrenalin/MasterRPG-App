// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

#if !os(tvOS)
@preconcurrency import PDFKit
#endif

struct PdfViewerView: View {
    init(model: ItemDataModel, entryId: UUID? = nil, withoutBookmark: Bool = false, dismissAction: (() -> Void)? = nil) {
        self.model = model
        self.entryId = entryId
        self.withoutBookmark = withoutBookmark
        self.dismissAction = dismissAction
        self._dataModelActor = State(wrappedValue: model.modelActor())
    }
    
    let model: ItemDataModel
    let entryId: UUID?
    let withoutBookmark: Bool
    let dismissAction: (() -> Void)?
    
    @Environment(PdfRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.showGame) private var showGame
    
    @State private var dataModelActor: DataModelActor?
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
            .searchable(text: $searchModel.displaySearchText, placement: .automatic, prompt: Text("Find in pdf", bundle: .module))
            .onSubmit(of: .search) {
                searchModel.resetSearch()
            }
        }
#if !os(visionOS)
        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
        .navigationTitle(Text(model.name))
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onChange(of: model, initial: true) {
            let id = model.id
            guard model.url != nil, let actor = model.modelActor() else {
                searchModel.pdfId = model.id
                return
            }
#if !os(tvOS)
            Task { @MainActor in
                let pdfTask = Task.detached {
                    await root.fileController.pdfDocument(itemId: id, actor: actor)
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
    var entry: PdfBookmarkDataModel? {
        guard let entryId else { return nil }
        return PdfBookmarkDataModel(itemId: model.id)
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
    @Previewable @Query var models: [ItemDataModel]
        
    PdfViewerView(model: models[0])
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
