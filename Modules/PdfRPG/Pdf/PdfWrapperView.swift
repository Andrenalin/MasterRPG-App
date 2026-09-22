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

// `@unchecked` because PDFKit doesn't declare Sendable itself, but this is relied on
// deliberately: `ItemController.pdfDocument(for:)` decodes `PDFDocument(url:)` inside a
// `Task.detached` to keep it off the MainActor, which requires the value to cross that
// isolation boundary. All decode/mutation of these types elsewhere in this module stays
// on the MainActor. See CODE_AUDIT_Pdf §3.1/§7.1.
extension PDFDocument: @unchecked @retroactive Sendable {}
extension PDFSelection: @unchecked @retroactive Sendable {}

struct PdfWrapperView: CustomViewRepresentable {
    /// Settle delay before navigating `PDFView` to a page or re-highlighting a search
    /// match — gives PDFKit's own layout/scroll a moment before driving it further.
    /// See CODE_AUDIT §9.14.
    private static let pdfViewNavigationDelay: Duration = .seconds(0.25)
    private static let minScaleFactor: CGFloat = 0.25
    private static let maxScaleFactor: CGFloat = 5.0
    let pdfDocument: PDFDocument?
    let horizontal: Bool
    let entry: PdfEntryModel?
    let searchModel: PdfSearchModel

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
        pdfView.minScaleFactor = Self.minScaleFactor
        pdfView.maxScaleFactor = Self.maxScaleFactor
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
        searchModel.pdfView = pdfView
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

        // Called by PDFKit off the main actor while a `beginFindString` scan is in
        // flight. Only append to `pendingMatches` here — PDFKit delivers these
        // sequentially for one scan, so the plain array is safe — and defer every
        // `PDFSelection.color` mutation to `documentDidEndDocumentFind`, which hops
        // to the main actor before touching it. See CODE_AUDIT_17 §3.8.
        func didMatchString(_ instance: PDFSelection) {
            pendingMatches.append(instance)
        }

        func documentDidEndDocumentFind(_ notification: Notification) {
            let matches = pendingMatches
            let pdfView = pdfView
            let searchModel = parent.searchModel
            Task { @MainActor in
                guard let pdfView else { return }
                for match in matches {
                    match.color = AKColor.yellow
                }
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
                    Task { @MainActor in
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
