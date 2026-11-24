// @copyright André Trettin

#if !os(tvOS)

import Evaluations
import Foundation
import FoundationModels
import TabularData
import Testing

@testable import GeneratorRPG

/// Knobs for the table evaluation, read from the environment (`TEST_RUNNER_` prefix under
/// xcodebuild).
enum TableSummaryEvaluationConfiguration {
    /// The evaluation calls the real on-device model and takes minutes, so it only runs on
    /// request: `TEST_RUNNER_TABLE_SUMMARY_EVAL=1`. The regular plans include this test target and skip it.
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["TABLE_SUMMARY_EVAL"] == "1"
    }

    /// How often each table is analyzed. `TABLE_SUMMARY_EVAL_RUNS`
    static var runs: Int {
        Int(ProcessInfo.processInfo.environment["TABLE_SUMMARY_EVAL_RUNS"] ?? "").map { max($0, 1) } ?? 3
    }

    /// Share of runs that must pass every rule. `TABLE_SUMMARY_EVAL_THRESHOLD`
    static var passRateThreshold: Double {
        Double(ProcessInfo.processInfo.environment["TABLE_SUMMARY_EVAL_THRESHOLD"] ?? "")
            .map { min(max($0, 0), 1) } ?? 0.8
    }

    /// Share of runs that may fail to produce an analysis at all (guardrail, simulator safety check).
    static let inferenceFailureTolerance = 0.2

    static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }
}

/// Runs `TableSummaryAnalyzer` on tables with known content and judges the title, description and
/// tags it produces. The results appear in Xcode's report navigator under Evaluations:
///
///     TEST_RUNNER_TABLE_SUMMARY_EVAL=1 xcodebuild test -scheme MasterRPG \
///       -destination 'platform=iOS Simulator,id=<iPhone 18 Pro id>' \
///       -only-testing:GeneratorRPGTests/TableSummaryEvaluationTests
///
/// The simulator reaches the host's model, but its safety check sometimes fails with "Simulator is
/// not supported"; those runs count as inference failures up to the tolerance.
@Suite(
    "Table summary evaluation",
    .tags(.evaluation),
    .serialized,
    .enabled(if: TableSummaryEvaluationConfiguration.isRequested, "Set TEST_RUNNER_TABLE_SUMMARY_EVAL=1 to run the evaluation")
)
struct TableSummaryEvaluationTests {
    static let evaluation = TableSummaryEvaluation(runs: TableSummaryEvaluationConfiguration.runs)

    @Test(
        "The on-device model titles, describes and tags the sample tables",
        .enabled(if: TableSummaryEvaluationConfiguration.isModelAvailable, "Apple Intelligence is not available"),
        .evaluates(Self.evaluation, info: ["model": "on-device", "runs": "\(TableSummaryEvaluationConfiguration.runs)"])
    )
    func summaryQuality() {
        let result = EvaluationContext.current.result
        let sampleCount = Double(TableSummarySample.dataset(runs: Self.evaluation.runs).count)
        let passRate = result.aggregateValue(.mean(of: Self.evaluation.passed))
        let titleRate = result.aggregateValue(.mean(of: Self.evaluation.titleRules))
        let descriptionRate = result.aggregateValue(.mean(of: Self.evaluation.descriptionRules))
        let tagRate = result.aggregateValue(.mean(of: Self.evaluation.tagRules))
        let recall = result.aggregateValue(.mean(of: Self.evaluation.concepts))
        let failedRuns = Double(result.errors.inferenceFailureCount)

        print(result.groupedSummary)
        let verdicts = result.detailed[metric: Self.evaluation.passed]
        for row in 0..<verdicts.count {
            if let verdict = verdicts[row], verdict.value == .failing {
                print("FAILED sample \(row + 1): \(verdict.rationale ?? "")")
            }
        }

        #expect(
            failedRuns / sampleCount <= TableSummaryEvaluationConfiguration.inferenceFailureTolerance,
            "\(Int(failedRuns)) of \(Int(sampleCount)) runs produced no analysis"
        )
        #expect(
            passRate >= TableSummaryEvaluationConfiguration.passRateThreshold,
            "\(passRate.formatted(.percent)) of runs passed (title rules \(titleRate.formatted(.percent)), description rules \(descriptionRate.formatted(.percent)), tag rules \(tagRate.formatted(.percent)), concept recall \(recall.formatted(.percent))), needs \(TableSummaryEvaluationConfiguration.passRateThreshold.formatted(.percent))"
        )
    }
}

#endif
