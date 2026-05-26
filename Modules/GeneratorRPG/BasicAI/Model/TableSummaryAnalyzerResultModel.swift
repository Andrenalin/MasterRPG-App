// @copyright André Trettin

import Foundation
import Observation

@MainActor @Observable
final class TableSummaryAnalyzerResultModel {
    var analysisProgress: TableSummaryAnalysis.PartiallyGenerated?
}
