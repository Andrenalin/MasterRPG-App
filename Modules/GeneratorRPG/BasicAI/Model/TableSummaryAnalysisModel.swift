// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

@MainActor @Observable
final class TableSummaryAnalysisModel {

    var isAnalyzing: Bool = false
    let resultModel: TableSummaryAnalyzerResultModel
    var lastError: String?

    private let analyzer: any TextSummaryAnalyzing

    /// - Parameter module: picks the analysis; Character has its own (`CharacterSummaryAnalyzer`).
    init(module: NetworkModules = .table) {
        analyzer = TextSummaryAnalyzers.analyzer(for: module)
        resultModel = TableSummaryAnalyzerResultModel()
    }

    /// - Parameter itemName: the item's current name, empty when it has none.
    func analyze(entriesText: String, itemName: String = "", outputLanguage: String = "English") async -> TableSummaryAnalysis? {
        isAnalyzing = true
        resultModel.analysisProgress = nil
        lastError = nil

        defer { isAnalyzing = false }

        do {
            return try await analyzer.analyze(entriesText: entriesText, itemName: itemName, resultModel: resultModel, outputLanguage: outputLanguage)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func clearError() {
        lastError = nil
    }
}
