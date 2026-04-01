// @copyright André Trettin

import Foundation
import Observation

@MainActor @Observable
final class PdfContentExtractionResultModel {
    var extractionProgress: [BlockGenModel]?
    var pageProgress: PdfAnalysisProgress?
}
