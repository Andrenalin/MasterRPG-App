// @copyright André Trettin

#if !os(tvOS)
import PDFKit
#endif
import SwiftUI

@MainActor @Observable
final class PdfSearchModel: Sendable {
#if os(tvOS)
    init(selectedEntry: PdfEntryModel? = nil) {
    }
#else
    init(pdfDoc: PDFDocument? = nil, selectedEntry: PdfEntryModel? = nil) {
        self.pdfDoc = pdfDoc
        self.selectedEntry = selectedEntry
    }
#endif
    
    private(set) var searchText: String = ""
    var isSearching: Bool = false
#if os(tvOS)
    var matches: [String] = []
#else
    var matches: [PDFSelection] = []
    var setSearchMatch: (([PDFSelection], Int) -> Void)?
#endif
    
    var currentIndex = 0
    var selectedEntry: PdfEntryModel?

    @ObservationIgnored var displaySearchText = ""
    @ObservationIgnored var pdfSearching = false

#if !os(tvOS)
    @ObservationIgnored var pdfView: PDFView?
    @ObservationIgnored var pdfDoc: PDFDocument?
    /// Set when the current item's PDF failed to download/decode, so the viewer can show
    /// `PdfUnavailableView` instead of spinning forever. See CODE_AUDIT_Pdf §5.3.
    var pdfUnavailable = false
#endif
    var pdfId = UUID()
    
    func resetSearch() {
        pdfSearching = false
        searchText = displaySearchText
    }
    
    func disabledNext() -> Bool {
#if os(tvOS)
        true
#else
        currentIndex >= matches.count - 1
#endif
    }
    
    func disabledPrev() -> Bool {
#if os(tvOS)
        true
#else
        currentIndex <= 0 || matches.isEmpty
#endif
    }
    
    func nextMatch() {
        guard !disabledNext() else { return }
        currentIndex += 1
#if !os(tvOS)
        setSearchMatch?(matches, currentIndex)
#endif
    }
    
    func previousMatch() {
        guard !disabledPrev() else { return }
        currentIndex -= 1
#if !os(tvOS)
        setSearchMatch?(matches, currentIndex)
#endif
    }
}
