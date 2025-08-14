// @copyright André Trettin

import CoreRPG

#if !os(tvOS)
@preconcurrency import PDFKit
#endif
import SwiftData
import SwiftUI

struct SelectionBar: View {
    let editController: EditController
    let model: PdfDataModel
    let searchModel: PdfSearchModel
    let withoutBookmark: Bool
    
    @Environment(PdfRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showGame) private var showGame
    
    var body: some View {
        textSelection
            .opacity((!withoutBookmark && searchModel.selectedEntry != nil) ? 1 : 0)
            .padding()
    }
}

private extension SelectionBar {
    @ViewBuilder
    var textSelection: some View {
        HStack {
            HStack {
                textContent
            }
            .padding(.horizontal)
#if !os(visionOS)
            .glassEffect(.regular)
#endif
            if !withoutBookmark && searchModel.selectedEntry != nil {
                bookmarkButton
            }
        }
        .padding(8)
    }
    
    @ViewBuilder
    var textContent: some View {
        if let currentPage = searchModel.selectedEntry?.pageLabel {
            Text(currentPage)
                .font(.title)
                .padding(8)
                .foregroundStyle(Color.accentColor)
        }
        if let currentSelection = searchModel.selectedEntry?.content {
            Text(currentSelection)
                .lineLimit(/*@START_MENU_TOKEN@*/2/*@END_MENU_TOKEN@*/)
                .foregroundStyle(Color.accentColor)
        }
    }
    
    var bookmarkButton: some View {
        Button {
            if let selectedEntry = searchModel.selectedEntry {
                editController.addBookmark(model: model, bookmark: selectedEntry)
            }
            withAnimation { searchModel.selectedEntry = nil }
        } label: {
            Image(systemName: "bookmark")
                .padding(12)
                .clipShape(.circle)
        }
#if !os(visionOS)
        .glassEffect(.regular.interactive())
#endif
    }
}


#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    @Previewable @Environment(PdfRootModel.self) var root
    @Previewable @State var searchModel = PdfSearchModel()
    
    NavigationStack {
        ZStack {
            ConcentricRectangle(corners: .concentric).fill(Color.red.gradient)
                .ignoresSafeArea(.container, edges: .top)
            
            VStack {
                Color.clear
                Button {
                    let entry = PdfBookmarkDataModel(id: UUID(), content: "This is the selection", pageLabel: "2")
                    searchModel.selectedEntry = entry
                } label: {
                    Text("Create")
                }
                Color.clear
            }
                .overlay(alignment: .top) {
                    SelectionBar(editController: root.editController, model: models[0], searchModel: PdfSearchModel(), withoutBookmark: true)
                        .padding(.top, 64)
                }
                .overlay(alignment: .bottom) {
                    SelectionBar(editController: root.editController, model: models[0], searchModel: searchModel, withoutBookmark: false)
                }
        }
    }
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
        
}
