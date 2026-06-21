// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import PDFKit
import QuickLook
import SwiftUI

#if os(macOS)
import AppKit
import QuickLookUI
#endif

#if os(macOS)
typealias CustomViewRepresentable = NSViewRepresentable
#else
typealias CustomViewRepresentable = UIViewRepresentable
#endif

extension PDFDocument: @unchecked @retroactive Sendable {}
extension PDFSelection: @unchecked @retroactive Sendable {}

struct PdfWrapperView: CustomViewRepresentable {
    let pdfDocument: PDFDocument?
    let horizontal: Bool
    let entry: PdfEntryModel?
    let searchModel: PdfSearchModel
    
    init(url: URL, entry: PdfEntryModel?, horizontal: Bool, searchModel: PdfSearchModel) {
        pdfDocument = PDFDocument(url: url)
        self.entry = entry
        self.horizontal = horizontal
        self.searchModel = searchModel
    }
    
    init(showing pdfDoc: PDFDocument, entry: PdfEntryModel?, horizontal: Bool, searchModel: PdfSearchModel) {
        pdfDocument = pdfDoc
        self.entry = entry
        self.horizontal = horizontal
        self.searchModel = searchModel
    }
    
#if os(macOS)
    func makeNSView(context _: Context) -> PDFView {
        makeView()
    }
#else
    func makeUIView(context _: Context) -> PDFView {
        makeView()
    }
#endif

    @MainActor
    func makeView() -> PDFView {
        let pdfView = PDFView()
        
        pdfView.document = pdfDocument
        pdfView.autoScales = false
        pdfView.autoresizesSubviews = true
        pdfView.displayDirection = horizontal ? .horizontal : .vertical
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 5.0
        pdfView.displayMode = .singlePageContinuous
#if os(iOS) || os(visionOS)
        pdfView.isFindInteractionEnabled = true
#endif
        
        if let entry, let pageNo = Int(entry.pageLabel) {
            if let page = pdfDocument?.page(at: pageNo - 1), let selection = page.selection(for: entry.bounds) {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.25))
                    pdfView.go(to: page)
                }
                selection.color = AKColor.yellow
                pdfView.highlightedSelections = [selection]
            }
        }
        Task { @MainActor in
            searchModel.pdfView = pdfView
        }
        return pdfView
    }
    
#if os(macOS)
    func updateNSView(_ pdfView: PDFView, context: Context) {
        updateView(pdfView, context: context)
    }
#else
    func updateUIView(_ pdfView: PDFView, context: Context) {
        updateView(pdfView, context: context)
    }
#endif

    @MainActor
    func updateView(_ pdfView: PDFView, context: Context) {
        pdfView.document?.delegate = context.coordinator
        pdfView.delegate = context.coordinator
        
        if !searchModel.pdfSearching && !searchModel.searchText.isEmpty {
            let searchText = searchModel.searchText
            Task { @MainActor in
                searchModel.pdfSearching = true
                searchModel.isSearching = true

                let matches = pdfView.document?.findString(searchText, withOptions: .caseInsensitive)
                matches?.forEach { match in
                    match.color = AKColor.yellow
                }
                if let match = matches?.first {
                    pdfView.go(to: match)
                }
                pdfView.highlightedSelections = matches
                Task { @MainActor in
                    if let matches {
                        searchModel.matches = matches
                        searchModel.currentIndex = 0
                        searchModel.setSearchMatch = { matches, index in
                            let selection = matches[index]
                            pdfView.go(to: selection)
                            selection.color = AKColor.clear
                            var updatedMatches = matches
                            updatedMatches[index] = selection
                            pdfView.highlightedSelections = updatedMatches
                            Task {
                                try? await Task.sleep(for: .seconds(0.25))
                                selection.color = AKColor.yellow
                                updatedMatches[index] = selection
                                pdfView.highlightedSelections = updatedMatches
                            }
                        }
                    }
                    searchModel.isSearching = false
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    final class Coordinator: NSObject, PDFViewDelegate, PDFDocumentDelegate {
        let parent: PdfWrapperView
        
        init(parent: PdfWrapperView) {
            self.parent = parent
        }
        
        @objc func handlePageChange(notification: Notification) {
            //parent.pageLabel(pdfView: parent.pdfView, viewSize: parent.viewSize)
        }
    }
}

#endif
