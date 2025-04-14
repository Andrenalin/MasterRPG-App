// @copyright André Trettin

import AndrenalinKit
#if !os(tvOS)
@preconcurrency import PDFKit
#endif
import SwiftUI

struct PdfViewerView: View {
    init(editController: EditController, model: PdfModel, entryId: UUID?, withoutBookmark: Bool, dismissAction: (() -> Void)? = nil) {
        self.editController = editController
        self.model = model
        self.entryId = entryId
        self.withoutBookmark = withoutBookmark
        self.dismissAction = dismissAction
    }
    
    let editController: EditController
    let model: PdfModel
    let entryId: UUID?
    let withoutBookmark: Bool
    let dismissAction: (() -> Void)?
    
    @Environment(PdfRoot.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showGame) private var showGame

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
    
    private var entry: PdfEntryModel? {
        guard let entryId else { return nil }
        return model[entryId]
    }
}
