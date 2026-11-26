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

    /// A character's progress: an existing name is shown instead of the generated one, and the
    /// tags are the parts generated so far.
    init(_ partial: CharacterSummaryAnalysis.PartiallyGenerated, existingName: String) {
        self.title = existingName.isEmpty ? partial.name : existingName
        self.description = partial.description
        let tags = CharacterSummaryAnalysis.tags(race: partial.race, occupation: partial.occupation, sex: partial.sex, traits: partial.traits)
        self.tags = tags.isEmpty ? nil : tags
    }
}

@MainActor @Observable
final class TableSummaryAnalyzerResultModel {
    var analysisProgress: TableSummaryAnalysisProgress?

    /// A cross-actor property *write* (unlike a read) can't be done with a plain
    /// `await obj.property = value` — only reads compose that way. `TableSummaryAnalyzer`
    /// calls this from off-actor with `await` instead of wrapping the assignment in
    /// `MainActor.run`. See CODE_AUDIT §3.2.
    func setAnalysisProgress(_ progress: TableSummaryAnalysisProgress) {
        analysisProgress = progress
    }
}
