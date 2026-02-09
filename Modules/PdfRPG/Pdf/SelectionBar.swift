// @copyright André Trettin

import CoreRPG

#if !os(tvOS)
@preconcurrency import PDFKit
#endif
import SwiftUI

struct SelectionBar: View {
    let editController: EditController
    let model: PdfModel
    let searchModel: PdfSearchModel
    let withoutBookmark: Bool
    
    @Environment(PdfRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
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
                editController.addBookmark(itemId: model.id, entry: selectedEntry)
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
    @Previewable @Environment(PdfRootModel.self) var root
    @Previewable @State var searchModel = PdfSearchModel()
    
    NavigationStack {
        ZStack {
            ConcentricRectangle(corners: .concentric).fill(Color.red.gradient)
                .ignoresSafeArea(.container, edges: .top)
            
            VStack {
                Color.clear
                Button {
                    let entry = PdfEntryModel(id: UUID(), name: "Hello", content: "This is the selection", pageNumber: "2", bounds: .zero, displayState: 0)
                    searchModel.selectedEntry = entry
                } label: {
                    Text("Create", bundle: .module)
                }
                Color.clear
            }
                .overlay(alignment: .top) {
                    SelectionBar(editController: root.editController, model: root.itemController.itemOrEmpty(for: PdfModel.previewId), searchModel: PdfSearchModel(), withoutBookmark: true)
                        .padding(.top, 64)
                }
                .overlay(alignment: .bottom) {
                    SelectionBar(editController: root.editController, model: root.itemController.itemOrEmpty(for: PdfModel.previewId), searchModel: searchModel, withoutBookmark: false)
                }
        }
    }
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
        
}
