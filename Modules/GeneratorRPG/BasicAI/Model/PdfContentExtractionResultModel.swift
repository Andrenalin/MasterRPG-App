// @copyright André Trettin

import Foundation
import Observation

@MainActor @Observable
final class PdfContentExtractionResultModel {
    var extractionProgress: [BlockEntryGenModel] = []
    var pageProgress: PdfAnalysisProgress = PdfAnalysisProgress(currentPage: 0, totalPages: 0)

    /// A cross-actor property *write* (unlike a read) can't be done with a plain
    /// `await obj.property = value` — only reads compose that way. `PdfContentExtractor`
    /// calls these from off-actor with `await` instead of wrapping the assignment in
    /// `MainActor.run`. See CODE_AUDIT §3.2.
    func setPageProgress(_ progress: PdfAnalysisProgress) {
        pageProgress = progress
    }

    func setExtractionProgress(_ blocks: [BlockEntryGenModel]) {
        extractionProgress = blocks
    }

    /// The numbers of the pages the last extraction could not analyse.
    private(set) var failedPages: [Int] = []

    func setFailedPages(_ pages: [Int]) {
        failedPages = pages
    }
}
