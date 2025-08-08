// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
@preconcurrency import PDFKit
#endif
import SwiftUI

struct PdfSearchHeaderView: View {
    let editController: EditController
    let model: PdfDataModel
    let searchModel: PdfSearchModel
    let entryId: UUID?
    let toolbarClose: Bool
    let withoutBookmark: Bool
    let dismissAction: (() -> Void)?
    
    @Environment(PdfRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showGame) private var showGame

    @State private var showThumbnail = false
        
    var body: some View {
        let _ = Self._printChanges()
        @Bindable var searchModel = searchModel
        
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                #if !os(macOS)
                if !toolbarClose {
                    closeButton
                }

                Text(model.name).bold()
                #endif
                
                TextField(text: $searchModel.displaySearchText, prompt: Text("Find in pdf", bundle: .module)) {
                    Text("Find in pdf", bundle: .module)
                }
                .overlay {
                    if searchModel.isSearching {
                        Color.black.opacity(0.2)
                            .background(.ultraThinMaterial)
                            .overlay {
                                ProgressView()
                                    .foregroundStyle(.white)
                            }
                    }
                }
                .onSubmit {
                    searchModel.resetSearch()
                }
            }
            .padding(8)

            if !searchModel.matches.isEmpty {
                HStack {
                    Spacer()
                    Text("\(searchModel.currentIndex + 1)/\(searchModel.matches.count) Matches:", bundle: .module)
                    Button {
                        withAnimation {
                            searchModel.previousMatch()
                        }
                    } label: {
                        Image(systemName: "arrow.left")
                            .imageScale(.large)
                    }
                    .padding(.horizontal, 8)
                    .disabled(searchModel.disabledPrev())
                    
                    Button {
                        withAnimation {
                            searchModel.nextMatch()
                        }
                    } label: {
                        Image(systemName: "arrow.right")
                            .imageScale(.large)
                    }
                    .padding(.horizontal, 8)
                    .disabled(searchModel.disabledNext())
                }
                .padding(8)
            }
            
            if !withoutBookmark {
                HStack {
                    Text("Selection:", bundle: .module)
                    
                    if let currentPage = searchModel.selectedEntry?.pageLabel {
                        Text(currentPage).bold()
                    }
                    if let currentSelection = searchModel.selectedEntry?.content {
                        Text(currentSelection)
                            .lineLimit(/*@START_MENU_TOKEN@*/2/*@END_MENU_TOKEN@*/)
                    }
                    Spacer()
                    Button {
                        if let selectedEntry = searchModel.selectedEntry {
                            //editController.addBookmark(itemId: model.id, entry: selectedEntry)
                        }
                        withAnimation { searchModel.selectedEntry = nil }
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .disabled(searchModel.selectedEntry == nil)
                }
                .padding(8)
            }
            
            Divider()
                .padding(.horizontal, 8)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if toolbarClose {
                    closeButton
                }
            }
        }
    }
}

private extension PdfSearchHeaderView {
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
