// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

#if !os(tvOS)
@preconcurrency import PDFKit
#endif

struct PdfViewerView: View {
    init(editController: EditController, model: PdfDataModel, entryId: UUID?, withoutBookmark: Bool, dismissAction: (() -> Void)? = nil) {
        self.editController = editController
        self.model = model
        self.entryId = entryId
        self.withoutBookmark = withoutBookmark
        self.dismissAction = dismissAction
        self._dataModelActor = State(wrappedValue: model.modelActor())
    }
    
    let editController: EditController
    let model: PdfDataModel
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
        //let _ = Self._printChanges()
        
        VStack(alignment: .leading, spacing: 0) {
            PdfSearchHeaderView(editController: editController, model: model, searchModel: searchModel, entryId: entryId, withoutBookmark: withoutBookmark, dismissAction: dismissAction)
            
            VStack {
#if !os(tvOS)
                PDFUIView(searchModel: searchModel, horizontal: false, entry: entry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(searchModel.pdfId)
#endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
#if !os(visionOS)
        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
        .onChange(of: model, initial: true) {
            let id = model.id
            guard let actor = model.modelActor() else { return }
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
    
    private var entry: PdfBookmarkDataModel? {
        guard let entryId else { return nil }
        return model.bookmarkOrNew(for: entryId)
    }
}
