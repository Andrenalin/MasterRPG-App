// @copyright André Trettin

import Foundation
import Observation

struct PdfSectionProgress: Equatable, Sendable {
    let heading: String?
    let summary: String?
    let pageNumber: Int?

    init(_ partial: PdfSection.PartiallyGenerated) {
        self.heading = partial.heading
        self.summary = partial.summary
        self.pageNumber = partial.pageNumber ?? nil
    }
}

struct PdfSummaryAnalysisProgress: Equatable, Sendable {
    let title: String?
    let summary: String?
    let tags: [String]?
    let sections: [PdfSectionProgress]?

    init(_ partial: PdfSummaryAnalysis.PartiallyGenerated) {
        self.title = partial.title
        self.summary = partial.summary
        self.tags = partial.tags
        self.sections = partial.sections?.map(PdfSectionProgress.init)
    }
}

@MainActor @Observable
final class PdfSummaryAnalyzyerResultModel {
    var analysisProgress: PdfSummaryAnalysisProgress?
    var pageProgress: PdfAnalysisProgress?
}
