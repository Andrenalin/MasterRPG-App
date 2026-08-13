// @copyright André Trettin

import Foundation
import Observation

@MainActor @Observable
final class TableSummaryAnalysisModel {

    var isAnalyzing: Bool = false
    let resultModel: TableSummaryAnalyzerResultModel
    var lastError: String?

    private let analyzer: TableSummaryAnalyzer

    init() {
        analyzer = TableSummaryAnalyzer()
        resultModel = TableSummaryAnalyzerResultModel()
    }

    func analyze(entriesText: String, outputLanguage: String = "English") async -> TableSummaryAnalysis? {
        isAnalyzing = true
        resultModel.analysisProgress = nil
        lastError = nil

        defer { isAnalyzing = false }

        do {
            return try await analyzer.analyze(entriesText: entriesText, resultModel: resultModel, outputLanguage: outputLanguage)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func clearError() {
        lastError = nil
    }
}
