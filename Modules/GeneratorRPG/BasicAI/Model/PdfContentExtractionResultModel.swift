// @copyright André Trettin

import Foundation
import Observation

@MainActor @Observable
final class PdfContentExtractionResultModel {
    var extractionProgress: [BlockEntryGenModel] = []
    var pageProgress: PdfAnalysisProgress = PdfAnalysisProgress(currentPage: 0, totalPages: 0)
}
