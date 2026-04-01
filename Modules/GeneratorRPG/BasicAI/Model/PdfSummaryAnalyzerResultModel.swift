// @copyright André Trettin

import Foundation
import Observation

@MainActor @Observable
final class PdfSummaryAnalyzyerResultModel {
    var analysisProgress: PdfSummaryAnalysis.PartiallyGenerated?
    var pageProgress: PdfAnalysisProgress?
}
