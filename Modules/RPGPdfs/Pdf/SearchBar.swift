// @copyright André Trettin

import AndrenalinKit

#if !os(tvOS)
@preconcurrency import PDFKit
#endif
import SwiftUI

struct SearchBar: View {
    let searchModel: PdfSearchModel
    
    @State private var showThumbnail = false
    @Environment(\.isSearching) private var isSearching
    
    var body: some View {
        if !searchModel.matches.isEmpty {
            searchResults
                .padding()
                .onChange(of: isSearching) {
                    guard !isSearching else { return }
                    withAnimation { searchModel.matches = [] }
                }
        }
    }
}

private extension SearchBar {
    @ViewBuilder
    var searchResults: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation {
                    searchModel.previousMatch()
                }
            } label: {
                Image(systemName: "arrow.left")
                    .padding(8)
                    .clipShape(.circle)
            }
            .padding(.horizontal, 8)
            .disabled(searchModel.disabledPrev())
#if !os(visionOS)
            .glassEffect(.regular.interactive())
#endif
            
            Text("\(searchModel.currentIndex + 1)/\(searchModel.matches.count)", bundle: .module)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .padding()
#if !os(visionOS)
                .glassEffect(.regular)
#endif
            
            Button {
                withAnimation {
                    searchModel.nextMatch()
                }
            } label: {
                Image(systemName: "arrow.right")
                    .padding(8)
                    .clipShape(.circle)
            }
            .padding(.horizontal, 8)
            .disabled(searchModel.disabledNext())
#if !os(visionOS)
            .glassEffect(.regular.interactive())
#endif
        }
        .padding(8)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    @Previewable @State var searchModel = PdfSearchModel()
    
    NavigationStack {
        ZStack {
            ConcentricRectangle(corners: .concentric).fill(Color.blue.gradient)
                .ignoresSafeArea(.container, edges: .top)
            
            VStack {
                Button {
                    let entry = PdfEntryModel(id: UUID(), name: "Hello", content: "This is the selection", pageNumber: "2", bounds: .zero, displayState: 0)
                    searchModel.selectedEntry = entry
                    #if !os(tvOS)
                    searchModel.matches = [PDFSelection()]
                    #endif
                } label: {
                    Text("Create")
                }
                Color.clear
            }
            .overlay(alignment: .top) {
                SearchBar(searchModel: PdfSearchModel())
                    .padding(.top, 64)
            }
            .overlay(alignment: .bottom) {
                SearchBar(searchModel: searchModel)
            }
        }
    }
#if os(macOS)
    .frame(width: 800, height: 600)
#endif
    
}
