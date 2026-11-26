// @copyright André Trettin

import CoreRPG
import Foundation

/// An on-device analysis that turns an item's text into a title, a description and tags. Most
/// modules use `TableSummaryAnalyzer`; Character has its own rules (`CharacterSummaryAnalyzer`).
protocol TextSummaryAnalyzing: Sendable {
    /// - Parameter itemName: the item's current name, empty when it has none.
    func analyze(
        entriesText: String,
        itemName: String,
        resultModel: TableSummaryAnalyzerResultModel,
        outputLanguage: String
    ) async throws -> TableSummaryAnalysis
}

enum TextSummaryAnalyzers {
    static func analyzer(for module: NetworkModules) -> any TextSummaryAnalyzing {
        switch module {
        case .value: CharacterSummaryAnalyzer()
        default: TableSummaryAnalyzer()
        }
    }
}

extension TableSummaryAnalyzer: TextSummaryAnalyzing {
    func analyze(
        entriesText: String,
        itemName _: String,
        resultModel: TableSummaryAnalyzerResultModel,
        outputLanguage: String
    ) async throws -> TableSummaryAnalysis {
        try await analyze(entriesText: entriesText, resultModel: resultModel, outputLanguage: outputLanguage)
    }
}
