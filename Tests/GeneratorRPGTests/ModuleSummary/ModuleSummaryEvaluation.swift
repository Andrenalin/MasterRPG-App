// @copyright André Trettin

#if !os(tvOS)

import Evaluations
import Foundation
import FoundationModels

@testable import GeneratorRPG

/// One adventure or map, analyzed once, with what the result should contain. As in
/// `TableSummarySample` there is no golden answer, only `expectations`, so `expected` stays `nil`.
struct ModuleSummarySample: ModelSampleProtocol {
    typealias ExpectedValue = TableSummaryAnalysis
    typealias Expectation = TableSummaryExpectation

    let fixture: ModuleSummaryFixture
    /// Distinguishes the repeated runs of one item, which the framework treats as separate samples.
    let runIndex: Int

    var input: ModelSampleInput {
        ModelSampleInput(prompt: Prompt("\(fixture.testDescription), run \(runIndex + 1)"))
    }

    var output: ModelSampleOutput<TableSummaryAnalysis, TableSummaryExpectation> {
        ModelSampleOutput(expectations: fixture.expectation)
    }

    var expected: TableSummaryAnalysis? { nil }
}

extension ModuleSummarySample {
    static func dataset(for kind: ModuleSummaryKind, runs: Int) -> [ModuleSummarySample] {
        (0..<runs).flatMap { run in
            ModuleSummaryFixture.all(for: kind).map { ModuleSummarySample(fixture: $0, runIndex: run) }
        }
    }
}

extension TableSummaryEvaluator {
    /// The table rules plus the words that only name the form of an adventure or a map: true of every
    /// item of the module, so they neither title nor tag one.
    static func forModule(_ kind: ModuleSummaryKind) -> TableSummaryEvaluator {
        var evaluator = TableSummaryEvaluator()
        let words: Set<String> = switch kind {
        case .adventure:
            [
                "adventure", "adventures", "rpg adventure", "scenario", "module", "campaign", "scenes", "chapters",
                "abenteuer", "rollenspielabenteuer", "szenario", "kampagne", "szenen", "kapitel"
            ]
        case .map:
            [
                "map", "maps", "rpg map", "dungeon map", "floor plan", "rooms", "room", "layout", "location",
                "karte", "karten", "landkarte", "grundriss", "raume", "raum", "ort"
            ]
        }
        evaluator.genericTitles.formUnion(words)
        // Table wording leaks into other modules' descriptions ("This table tracks…").
        evaluator.misnamingWords = ["table", "tables", "tabelle", "tabellen"]
        if kind == .adventure {
            // An adventure's description is a short summary of its story.
            evaluator.maximumDescriptionSentences = 3
            evaluator.maximumDescriptionCharacters = 400
        }
        evaluator.tagEvaluator.genericTags.formUnion(words)
        return evaluator
    }
}

extension MapPlaceKind: @retroactive Codable {}
extension AdventurePlotKind: @retroactive Codable {}

extension TableSummaryEvaluator {
    /// The adventure rules on top of `forModule(.adventure)`: the tags start with the expected
    /// level band and character count (as the fixture writes them out, not as the analyzer computes
    /// them), then the type of adventure in the output language; no later tag is a level or a count.
    static func adventureViolations(
        tags: [String],
        partyTags: [String],
        acceptedKinds: [AdventurePlotKind],
        outputLanguage: String
    ) -> [String] {
        var violations: [String] = []
        let leading = Array(tags.prefix(partyTags.count))
        if leading != partyTags {
            violations.append("starts with \(leading) instead of the level and count \(partyTags)")
        }
        let rest = tags.dropFirst(partyTags.count)
        if !acceptedKinds.isEmpty {
            let names = acceptedKinds.map { $0.name(in: outputLanguage) }
            if !names.contains(where: { rest.first == $0 }) {
                violations.append("tag '\(rest.first ?? "")' after the level and count is not the type (\(names.joined(separator: " or ")))")
            }
        }
        for tag in rest.dropFirst() where looksLikePartyTag(tag) {
            violations.append("'\(tag)' is a level or character count in the wrong place")
        }
        return violations
    }

    /// "1-4", "Level 3", "Stufe 5", "4 PC", "3-5 SC".
    private static func looksLikePartyTag(_ tag: String) -> Bool {
        let words = tag.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let partyWords: Set<String> = ["level", "levels", "stufe", "stufen", "pc", "pcs", "sc", "players", "spieler", "characters", "charaktere"]
        let onlyNumbers = !words.isEmpty && words.allSatisfy { $0.allSatisfy(\.isNumber) }
        return onlyNumbers || words.contains { partyWords.contains($0) }
    }
}

extension TableSummaryEvaluator {
    /// Whole words that call a map a map. Deliberately not `MapSummaryGeneration.formWords`, so the
    /// evaluation judges the analyzer's cleanup instead of repeating it.
    static let mapFormWords: Set<String> = ["map", "maps", "karte", "karten", "landkarte", "layout", "grundriss"]

    /// The map rules on top of `forModule(.map)`: the first tag is the kind of place, written in
    /// the output language, and neither the title nor a tag uses a word for "map".
    static func mapViolations(
        title: String,
        tags: [String],
        acceptedKinds: [MapPlaceKind],
        outputLanguage: String
    ) -> (title: [String], tags: [String]) {
        var titleViolations: [String] = []
        var tagViolations: [String] = []
        if let word = mapFormWord(in: title) {
            titleViolations.append("uses the word '\(word)'")
        }
        for tag in tags {
            if let word = mapFormWord(in: tag) {
                tagViolations.append("'\(tag)' uses the word '\(word)'")
            }
        }
        if !acceptedKinds.isEmpty {
            let names = acceptedKinds.map { $0.name(in: outputLanguage) }
            if !names.contains(where: { tags.first == $0 }) {
                tagViolations.append("first tag '\(tags.first ?? "")' is not the kind of place (\(names.joined(separator: " or ")))")
            }
        }
        return (titleViolations, tagViolations)
    }

    private static func mapFormWord(in text: String) -> String? {
        text.split { !$0.isLetter }
            .map { PdfTagEvaluator.normalized(String($0)) }
            .first { mapFormWords.contains($0) }
    }
}

/// Scores the title, description and tags the generic text analysis produces for the sample
/// adventures or maps: the analysis behind their "Extract Information" (single item and batch).
/// The analyzer comes from `TextSummaryAnalyzers.analyzer(for:)`, so a module that gets its own
/// analyzer is evaluated with it. The rules are `TableSummaryEvaluator.forModule(_:)`.
struct ModuleSummaryEvaluation: Evaluation {
    typealias Sample = ModuleSummarySample
    typealias Subject = ModelSubject<TableSummaryAnalysis>

    let kind: ModuleSummaryKind
    let runs: Int

    /// Share of runs that pass every rule and find the expected concepts.
    let passed: Metric
    /// Share of runs whose title breaks no rule.
    let titleRules: Metric
    /// Share of runs whose description breaks no rule.
    let descriptionRules: Metric
    /// Share of runs whose tags break no rule.
    let tagRules: Metric
    /// How much of the expected concepts title, description and tags found, 0...1.
    let concepts: Metric

    init(kind: ModuleSummaryKind, runs: Int) {
        self.kind = kind
        self.runs = runs
        let prefix = kind.metricPrefix
        passed = Metric("\(prefix)SummaryPass")
        titleRules = Metric("\(prefix)TitleRules")
        descriptionRules = Metric("\(prefix)DescriptionRules")
        tagRules = Metric("\(prefix)TagRules")
        concepts = Metric("\(prefix)ConceptRecall")
    }

    var name: String { "\(kind.textTitle) summary" }

    var dataset: ArrayLoader<ModuleSummarySample> {
        ArrayLoader(samples: ModuleSummarySample.dataset(for: kind, runs: runs))
    }

    nonisolated(nonsending)
    func subject(from sample: ModuleSummarySample) async throws -> ModelSubject<TableSummaryAnalysis> {
        let resultModel = await MainActor.run { TableSummaryAnalyzerResultModel() }
        let analysis = try await TextSummaryAnalyzers.analyzer(for: sample.fixture.kind.module).analyze(
            entriesText: sample.fixture.entriesText,
            itemName: sample.fixture.itemName,
            resultModel: resultModel,
            outputLanguage: sample.fixture.outputLanguage
        )
        return ModelSubject(value: analysis)
    }

    var evaluators: Evaluators {
        Evaluator<ModuleSummarySample> { [passed] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.passed ? passed.passing() : passed.failing(rationale: Self.rationale(result))
        }
        Evaluator<ModuleSummarySample> { [titleRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.titleRuleViolations.isEmpty
                ? titleRules.passing()
                : titleRules.failing(rationale: "title: \(result.title); " + result.titleRuleViolations.joined(separator: "; "))
        }
        Evaluator<ModuleSummarySample> { [descriptionRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.descriptionRuleViolations.isEmpty
                ? descriptionRules.passing()
                : descriptionRules.failing(rationale: "description: \(result.description); " + result.descriptionRuleViolations.joined(separator: "; "))
        }
        Evaluator<ModuleSummarySample> { [tagRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.tagRuleViolations.isEmpty
                ? tagRules.passing()
                : tagRules.failing(rationale: "tags: \(result.tags.joined(separator: ", ")); " + result.tagRuleViolations.joined(separator: "; "))
        }
        Evaluator<ModuleSummarySample> { [concepts] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return concepts.scoring(
                result.conceptScore,
                rationale: "title: \(result.title); tags: \(result.tags.joined(separator: ", "))"
            )
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: passed)
        aggregator.computeMean(of: titleRules)
        aggregator.computeMean(of: descriptionRules)
        aggregator.computeMean(of: tagRules)
        aggregator.computeMean(of: concepts)
    }

    // MARK: - Helpers

    static func evaluate(_ analysis: TableSummaryAnalysis, for sample: ModuleSummarySample) -> TableSummaryVerdict {
        evaluate(title: analysis.title, description: analysis.description, tags: analysis.tags, fixture: sample.fixture)
    }

    /// The module's rules, and for a map also `TableSummaryEvaluator.mapViolations`, for an
    /// adventure `TableSummaryEvaluator.adventureViolations`.
    static func evaluate(title: String, description: String, tags: [String], fixture: ModuleSummaryFixture) -> TableSummaryVerdict {
        let verdict = TableSummaryEvaluator.forModule(fixture.kind).evaluate(
            title: title,
            description: description,
            tags: tags,
            expectation: fixture.expectation
        )
        guard fixture.kind == .map else {
            let adventure = TableSummaryEvaluator.adventureViolations(
                tags: tags,
                partyTags: fixture.partyTags,
                acceptedKinds: fixture.adventureKinds,
                outputLanguage: fixture.outputLanguage
            )
            return TableSummaryVerdict(
                title: verdict.title,
                description: verdict.description,
                tags: verdict.tags,
                titleRuleViolations: verdict.titleRuleViolations,
                descriptionRuleViolations: verdict.descriptionRuleViolations,
                tagRuleViolations: verdict.tagRuleViolations + adventure,
                conceptViolations: verdict.conceptViolations,
                conceptScore: verdict.conceptScore
            )
        }
        let map = TableSummaryEvaluator.mapViolations(
            title: title,
            tags: tags,
            acceptedKinds: fixture.mapKinds,
            outputLanguage: fixture.outputLanguage
        )
        return TableSummaryVerdict(
            title: verdict.title,
            description: verdict.description,
            tags: verdict.tags,
            titleRuleViolations: verdict.titleRuleViolations + map.title,
            descriptionRuleViolations: verdict.descriptionRuleViolations,
            tagRuleViolations: verdict.tagRuleViolations + map.tags,
            conceptViolations: verdict.conceptViolations,
            conceptScore: verdict.conceptScore
        )
    }

    static func rationale(_ result: TableSummaryVerdict) -> String {
        "title: \(result.title); description: \(result.description); tags: \(result.tags.joined(separator: ", ")); "
            + result.violations.joined(separator: "; ")
    }
}

#endif
