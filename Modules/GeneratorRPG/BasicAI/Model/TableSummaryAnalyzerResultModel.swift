// @copyright André Trettin

import Foundation
import Observation

struct TableSummaryAnalysisProgress: Equatable, Sendable {
    let title: String?
    let description: String?
    let tags: [String]?

    init(_ partial: TableSummaryAnalysis.PartiallyGenerated) {
        self.title = partial.title
        self.description = partial.description
        self.tags = partial.tags
    }
}

@MainActor @Observable
final class TableSummaryAnalyzerResultModel {
    var analysisProgress: TableSummaryAnalysisProgress?
}
