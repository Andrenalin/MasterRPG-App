// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import PDFKit
import QuickLook
import SwiftUI
import Synchronization

#if os(macOS)
import AppKit
import QuickLookUI
#endif

#if os(macOS)
typealias CustomViewRepresentable = NSViewRepresentable
#else
typealias CustomViewRepresentable = UIViewRepresentable
#endif

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
        
        if let entry, let pdfDocument, let page = PdfBookmarkPage.page(for: entry, in: pdfDocument) {
            // Also when the selection cannot be rebuilt from the stored bounds: the bookmark
            // then still opens its page. See CODE_AUDIT_21 §5.17.
            Task { @MainActor in
                try? await Task.sleep(for: Self.pdfViewNavigationDelay)
                pdfView.go(to: page)
            }
            if let selection = page.selection(for: entry.bounds) {
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
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PDFViewDelegate, PDFDocumentDelegate {
        let parent: PdfWrapperView
        weak var pdfView: PDFView?
        /// Accumulated across `didMatchString(_:)` calls for the search currently in flight.
        /// PDFKit appends from its search thread while `beginSearch` resets it on the main
        /// thread, so it is lock-protected; `beginSearch` also cancels the previous scan so
        /// its late matches can't leak into the new one. See CODE_AUDIT_9 §5.4 and
        /// CODE_AUDIT_18 §3.9.
        private let pendingMatches = Mutex<[MatchHandoff.Selection]>([])

        /// Hands a finished scan's matches from PDFKit's search thread to the main actor.
        /// `PDFSelection` isn't `Sendable`; this is sound because nothing touches the
        /// selections off the main actor after the handoff (the scan has ended and the
        /// buffer is cleared). Replaces the former app-wide retroactive conformances on
        /// PDFKit types. See CODE_AUDIT_18 §3.9.
        private struct MatchHandoff: @unchecked Sendable {
            /// One match, wrapped so the buffer's `Mutex` can hold it.
            struct Selection: @unchecked Sendable {
                let value: PDFSelection
            }

            let selections: [PDFSelection]
        }

        init(parent: PdfWrapperView) {
            self.parent = parent
        }

        /// Started by `PdfSearchModel.beginFindIfNeeded()` from the viewer's `.task(id:)`, not from
        /// `updateView`. See CODE_AUDIT_26 §8.29.
        /// `beginFindString(_:withOptions:)` searches asynchronously off the main thread, unlike
        /// `findString(_:withOptions:)` (used previously), which blocks the caller for the full scan,
        /// a real hitch on a large rulebook PDF. Matches arrive one at a time via
        /// `didMatchString(_:)`, finalized in `documentDidEndDocumentFind(_:)`. See CODE_AUDIT_9 §5.4.
        @MainActor func beginSearch(_ searchText: String) {
            pdfView?.document?.cancelFindString()
            pendingMatches.withLock { $0.removeAll() }
            pdfView?.document?.beginFindString(searchText, withOptions: .caseInsensitive)
        }

        // Called by PDFKit off the main actor while a `beginFindString` scan is in
        // flight. Only append to `pendingMatches` here, and defer every
        // `PDFSelection.color` mutation to `documentDidEndDocumentFind`, which hops
        // to the main actor before touching it. See CODE_AUDIT_17 §3.8.
        func didMatchString(_ instance: PDFSelection) {
            pendingMatches.withLock { matches in
                // A one-letter query on a long PDF would otherwise keep every selection and
                // re-assign them all on each next/previous step. See CODE_AUDIT_23 §5.26.
                guard matches.count < Self.maximumMatches else { return }
                matches.append(MatchHandoff.Selection(value: instance))
            }
        }

        /// Most matches kept per search.
        private static let maximumMatches = 1_000

        func documentDidEndDocumentFind(_ notification: Notification) {
            // The end of a cancelled scan can arrive while the next scan is already running; it
            // would publish that scan's partial matches and stop the spinner early.
            // See CODE_AUDIT_23 §5.26.
            if let document = notification.object as? PDFDocument, document.isFinding { return }
            // Not drained: `cancelFindString` in `beginSearch` can deliver the end of the cancelled
            // scan after the new scan has started, and draining there took the new scan's matches
            // and left its real end with the rest. The buffer holds the matches of the current scan
            // until `beginSearch` clears it, so the last end notification shows all of them.
            let handoff = pendingMatches.withLock { matches in
                MatchHandoff(selections: matches.map(\.value))
            }
            let pdfView = pdfView
            let searchModel = parent.searchModel
            Task { @MainActor in
                guard let pdfView else { return }
                let matches = handoff.selections
                for match in matches {
                    match.color = AKColor.yellow
                }
                if let match = matches.first {
                    pdfView.go(to: match)
                }
                pdfView.highlightedSelections = matches
                searchModel.matches = matches
                searchModel.currentIndex = 0
                // Weak: the closure is stored on `searchModel`, which can outlive the viewer;
                // a strong capture kept the `PDFView` and its whole document alive.
                // See CODE_AUDIT_18 §3.9.
                searchModel.setSearchMatch = { [weak pdfView] matches, index in
                    guard let pdfView, matches.indices.contains(index) else { return }
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
