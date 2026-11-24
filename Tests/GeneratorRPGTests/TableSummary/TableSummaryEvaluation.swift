// @copyright André Trettin

#if !os(tvOS)

import Evaluations
import Foundation
import FoundationModels

@testable import GeneratorRPG

/// One table, analyzed once, with what the result should contain.
///
/// `ExpectedValue` is the analysis type because the framework compares a sample's expected value
/// with the subject's value; there is no golden answer here, only `expectations` (concept groups
/// as in the PDF evaluation), so `expected` stays `nil`.
struct TableSummarySample: ModelSampleProtocol {
    typealias ExpectedValue = TableSummaryAnalysis
    typealias Expectation = TableSummaryExpectation

    let fixture: TableSummaryFixture
    /// Distinguishes the repeated runs of one table, which the framework treats as separate samples.
    let runIndex: Int

    var input: ModelSampleInput {
        ModelSampleInput(prompt: Prompt("Table \(fixture.testDescription), run \(runIndex + 1)"))
    }

    var output: ModelSampleOutput<TableSummaryAnalysis, TableSummaryExpectation> {
        ModelSampleOutput(expectations: fixture.expectation)
    }

    var expected: TableSummaryAnalysis? { nil }
}

extension TableSummarySample {
    static func dataset(runs: Int) -> [TableSummarySample] {
        (0..<runs).flatMap { run in
            TableSummaryFixture.all.map { TableSummarySample(fixture: $0, runIndex: run) }
        }
    }
}

/// Scores the title, description and tags `TableSummaryAnalyzer` produces for the sample tables.
/// The rules are in `TableSummaryEvaluator`.
struct TableSummaryEvaluation: Evaluation {
    typealias Sample = TableSummarySample
    typealias Subject = ModelSubject<TableSummaryAnalysis>

    let runs: Int

    /// Share of runs that pass every rule and find the expected concepts.
    let passed = Metric("TableSummaryPass")
    /// Share of runs whose title breaks no rule.
    let titleRules = Metric("TableTitleRules")
    /// Share of runs whose description breaks no rule.
    let descriptionRules = Metric("TableDescriptionRules")
    /// Share of runs whose tags break no rule.
    let tagRules = Metric("TableTagRules")
    /// How much of the expected concepts title, description and tags found, 0...1.
    let concepts = Metric("TableConceptRecall")

    var name: String { "Table summary" }

    var dataset: ArrayLoader<TableSummarySample> {
        ArrayLoader(samples: TableSummarySample.dataset(runs: runs))
    }

    nonisolated(nonsending)
    func subject(from sample: TableSummarySample) async throws -> ModelSubject<TableSummaryAnalysis> {
        let resultModel = await MainActor.run { TableSummaryAnalyzerResultModel() }
        let analysis = try await TableSummaryAnalyzer().analyze(
            entriesText: sample.fixture.entriesText,
            resultModel: resultModel,
            outputLanguage: sample.fixture.outputLanguage
        )
        return ModelSubject(value: analysis)
    }

    var evaluators: Evaluators {
        Evaluator<TableSummarySample> { [passed] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.passed ? passed.passing() : passed.failing(rationale: Self.rationale(result))
        }
        Evaluator<TableSummarySample> { [titleRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.titleRuleViolations.isEmpty
                ? titleRules.passing()
                : titleRules.failing(rationale: "title: \(result.title); " + result.titleRuleViolations.joined(separator: "; "))
        }
        Evaluator<TableSummarySample> { [descriptionRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.descriptionRuleViolations.isEmpty
                ? descriptionRules.passing()
                : descriptionRules.failing(rationale: "description: \(result.description); " + result.descriptionRuleViolations.joined(separator: "; "))
        }
        Evaluator<TableSummarySample> { [tagRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.tagRuleViolations.isEmpty
                ? tagRules.passing()
                : tagRules.failing(rationale: "tags: \(result.tags.joined(separator: ", ")); " + result.tagRuleViolations.joined(separator: "; "))
        }
        Evaluator<TableSummarySample> { [concepts] sample, subject in
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

    static func evaluate(_ analysis: TableSummaryAnalysis, for sample: TableSummarySample) -> TableSummaryVerdict {
        TableSummaryEvaluator().evaluate(
            title: analysis.title,
            description: analysis.description,
            tags: analysis.tags,
            expectation: sample.fixture.expectation
        )
    }

    static func rationale(_ result: TableSummaryVerdict) -> String {
        "title: \(result.title); description: \(result.description); tags: \(result.tags.joined(separator: ", ")); "
            + result.violations.joined(separator: "; ")
    }
}

#endif
