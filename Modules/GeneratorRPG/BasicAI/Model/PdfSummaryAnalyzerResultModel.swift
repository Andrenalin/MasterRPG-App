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
        // Kind and genre lead the tags, filtered like the final result (no output language while
        // streaming, so an unusable kind is left out until the result replaces it).
        self.tags = partial.tags.map {
            PdfSummaryAnalysis.tags(
                category: partial.category,
                documentKind: partial.documentKind,
                genre: partial.genre,
                tags: $0,
                title: partial.title ?? "",
                outputLanguage: nil
            )
        }
        self.sections = partial.sections?.map(PdfSectionProgress.init)
    }
}

@MainActor @Observable
final class PdfSummaryAnalyzerResultModel {
    var analysisProgress: PdfSummaryAnalysisProgress?
    var pageProgress: PdfAnalysisProgress?

    /// A cross-actor property *write* (unlike a read) can't be done with a plain
    /// `await obj.property = value` — only reads compose that way. `PdfSummaryAnalyzer`
    /// calls these from off-actor with `await` instead of wrapping the assignment in
    /// `MainActor.run`. See CODE_AUDIT §3.2.
    func setPageProgress(_ progress: PdfAnalysisProgress) {
        pageProgress = progress
    }

    func setAnalysisProgress(_ progress: PdfSummaryAnalysisProgress) {
        analysisProgress = progress
    }
}
