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
    /// Settle delay before navigating `PDFView` to a page or re-highlighting a search
    /// match — gives PDFKit's own layout/scroll a moment before driving it further.
    /// See CODE_AUDIT §9.14.
    private static let pdfViewNavigationDelay: Duration = .seconds(0.25)
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
                    try? await Task.sleep(for: Self.pdfViewNavigationDelay)
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
        context.coordinator.pdfView = pdfView

        if !searchModel.pdfSearching && !searchModel.searchText.isEmpty {
            searchModel.pdfSearching = true
            searchModel.isSearching = true
            // `beginFindString(_:withOptions:)` searches asynchronously off the main
            // thread, unlike `findString(_:withOptions:)` (used previously), which
            // blocks the caller for the full scan — a real hitch on a large,
            // multi-page rulebook PDF even inside a `Task { @MainActor in }`, since
            // that only defers scheduling and doesn't move the work off-thread.
            // Matches arrive one at a time via `Coordinator.didMatchString(_:)`,
            // finalized in `documentDidEndDocumentFind(_:)`. See CODE_AUDIT_9 §5.4.
            context.coordinator.beginSearch(searchModel.searchText)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PDFViewDelegate, PDFDocumentDelegate {
        let parent: PdfWrapperView
        weak var pdfView: PDFView?
        /// Accumulated across `didMatchString(_:)` calls for the search currently
        /// in flight; PDFKit delivers these as one sequential scan, so a plain
        /// (non-actor-isolated) array is safe here — no two matches for the same
        /// search arrive concurrently. See CODE_AUDIT_9 §5.4.
        private var pendingMatches: [PDFSelection] = []

        init(parent: PdfWrapperView) {
            self.parent = parent
        }

        @MainActor func beginSearch(_ searchText: String) {
            pendingMatches = []
            pdfView?.document?.beginFindString(searchText, withOptions: .caseInsensitive)
        }

        func didMatchString(_ instance: PDFSelection) {
            instance.color = AKColor.yellow
            pendingMatches.append(instance)
        }

        func documentDidEndDocumentFind(_ notification: Notification) {
            let matches = pendingMatches
            let pdfView = pdfView
            let searchModel = parent.searchModel
            Task { @MainActor in
                guard let pdfView else { return }
                if let match = matches.first {
                    pdfView.go(to: match)
                }
                pdfView.highlightedSelections = matches
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
                        try? await Task.sleep(for: PdfWrapperView.pdfViewNavigationDelay)
                        selection.color = AKColor.yellow
                        updatedMatches[index] = selection
                        pdfView.highlightedSelections = updatedMatches
                    }
                }
                searchModel.isSearching = false
            }
        }
    }
}

#endif
