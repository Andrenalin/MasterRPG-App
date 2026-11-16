// @copyright André Trettin

import CoreRPG

#if !os(tvOS)
import PDFKit
#endif
import SwiftUI

struct SelectionBar: View {
    let editController: EditController
    let model: PdfModel
    let searchModel: PdfSearchModel
    let withoutBookmark: Bool
    
    var body: some View {
        SelectionBarTextSelectionView(editController: editController, model: model, searchModel: searchModel, withoutBookmark: withoutBookmark)
            .opacity(showsSelection ? 1 : 0)
            .allowsHitTesting(showsSelection)
            .accessibilityHidden(!showsSelection)
            .padding()
    }

    private var showsSelection: Bool {
        !withoutBookmark && searchModel.selectedEntry != nil
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct SelectionBarTextSelectionView: View {
    let editController: EditController
    let model: PdfModel
    let searchModel: PdfSearchModel
    let withoutBookmark: Bool

    var body: some View {
        HStack {
            HStack {
                SelectionBarTextContentView(searchModel: searchModel)
            }
            .padding(.horizontal)
#if !os(visionOS)
            .glassEffect(.regular)
#endif
            if !withoutBookmark && searchModel.selectedEntry != nil {
                SelectionBarBookmarkButtonView(editController: editController, model: model, searchModel: searchModel)
            }
        }
        .padding(8)
    }
}

private struct SelectionBarTextContentView: View {
    let searchModel: PdfSearchModel

    @ViewBuilder
    var body: some View {
        if let currentPage = searchModel.selectedEntry?.pageLabel {
            Text(verbatim: currentPage)
                .font(.title)
                .padding(8)
                .foregroundStyle(Color.accentColor)
        }
        if let currentSelection = searchModel.selectedEntry?.content {
            Text(verbatim: currentSelection)
                .lineLimit(2)
                .foregroundStyle(Color.accentColor)
        }
    }
}

private struct SelectionBarBookmarkButtonView: View {
    let editController: EditController
    let model: PdfModel
    let searchModel: PdfSearchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if let selectedEntry = searchModel.selectedEntry {
                editController.addBookmark(itemId: model.id, entry: selectedEntry)
            }
            withAnimation(reduceMotion ? nil : .default) {
                searchModel.selectedEntry = nil
            }
        } label: {
            Label {
                Text("Add bookmark", bundle: .module)
            } icon: {
                Image(systemName: "bookmark")
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.circle)
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
