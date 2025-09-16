// @copyright André Trettin

//import CoreRPG
#if !os(tvOS)
import PDFKit
#endif
import SwiftUI

@MainActor @Observable
final class PdfSearchModel: Sendable {
    init(pdfDoc: PDFDocument? = nil, selectedEntry: PdfEntryDataModel? = nil) {
        self.pdfDoc = pdfDoc
    }
    
    private(set) var searchText: String = ""
    var isSearching: Bool = false
#if os(tvOS)
    var matches: [String] = []
#else
    var matches: [PDFSelection] = []
    var setSearchMatch: (([PDFSelection], Int) -> Void)?
#endif
    
    var currentIndex = 0
    var selectedEntry: PdfEntryDataModel?

    @ObservationIgnored var displaySearchText = ""
    @ObservationIgnored var pdfSearching = false

#if !os(tvOS)
    @ObservationIgnored var pdfView: PDFView?
    @ObservationIgnored var pdfDoc: PDFDocument?
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
