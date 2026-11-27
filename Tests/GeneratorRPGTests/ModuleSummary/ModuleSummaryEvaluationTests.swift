// @copyright André Trettin

#if !os(tvOS)

import Evaluations
import Foundation
import FoundationModels
import TabularData
import Testing

@testable import GeneratorRPG

/// Knobs for the adventure and map evaluations, read from the environment (`TEST_RUNNER_` prefix
/// under xcodebuild). Each module has its own switch; runs and threshold are shared.
enum ModuleSummaryEvaluationConfiguration {
    /// The evaluations call the real on-device model and take minutes, so they only run on request:
    /// `TEST_RUNNER_ADVENTURE_SUMMARY_EVAL=1`, `TEST_RUNNER_MAP_SUMMARY_EVAL=1`. The regular plans
    /// include this test target and skip them.
    static func isRequested(_ kind: ModuleSummaryKind) -> Bool {
        ProcessInfo.processInfo.environment["\(environmentPrefix(kind))_SUMMARY_EVAL"] == "1"
    }

    /// How often each item is analyzed. `MODULE_SUMMARY_EVAL_RUNS`
    static var runs: Int {
        Int(ProcessInfo.processInfo.environment["MODULE_SUMMARY_EVAL_RUNS"] ?? "").map { max($0, 1) } ?? 3
    }

    /// Share of runs that must pass every rule. `MODULE_SUMMARY_EVAL_THRESHOLD`
    static var passRateThreshold: Double {
        Double(ProcessInfo.processInfo.environment["MODULE_SUMMARY_EVAL_THRESHOLD"] ?? "")
            .map { min(max($0, 0), 1) } ?? 0.8
    }

    /// Share of runs that may fail to produce an analysis at all (guardrail, simulator safety check).
    static let inferenceFailureTolerance = 0.2

    static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    private static func environmentPrefix(_ kind: ModuleSummaryKind) -> String {
        switch kind {
        case .adventure: "ADVENTURE"
        case .map: "MAP"
        }
    }

    /// Checks the evaluation's result against the tolerance and threshold and prints the failed samples.
    static func check(_ evaluation: ModuleSummaryEvaluation) {
        let result = EvaluationContext.current.result
        let sampleCount = Double(ModuleSummarySample.dataset(for: evaluation.kind, runs: evaluation.runs).count)
        let passRate = result.aggregateValue(.mean(of: evaluation.passed))
        let titleRate = result.aggregateValue(.mean(of: evaluation.titleRules))
        let descriptionRate = result.aggregateValue(.mean(of: evaluation.descriptionRules))
        let tagRate = result.aggregateValue(.mean(of: evaluation.tagRules))
        let recall = result.aggregateValue(.mean(of: evaluation.concepts))
        let failedRuns = Double(result.errors.inferenceFailureCount)

        print(result.groupedSummary)
        let verdicts = result.detailed[metric: evaluation.passed]
        for row in 0..<verdicts.count {
            if let verdict = verdicts[row], verdict.value == .failing {
                print("FAILED sample \(row + 1): \(verdict.rationale ?? "")")
            }
        }

        #expect(
            failedRuns / sampleCount <= inferenceFailureTolerance,
            "\(Int(failedRuns)) of \(Int(sampleCount)) runs produced no analysis"
        )
        #expect(
            passRate >= passRateThreshold,
            "\(passRate.formatted(.percent)) of runs passed (title rules \(titleRate.formatted(.percent)), description rules \(descriptionRate.formatted(.percent)), tag rules \(tagRate.formatted(.percent)), concept recall \(recall.formatted(.percent))), needs \(passRateThreshold.formatted(.percent))"
        )
    }
}

/// Runs the Adventure "Extract Information" analysis on adventures with known content and judges
/// the title, description and tags. Results appear in Xcode's report navigator under Evaluations:
///
///     TEST_RUNNER_ADVENTURE_SUMMARY_EVAL=1 xcodebuild test -scheme MasterRPG \
///       -destination 'platform=iOS Simulator,id=<iPhone 18 Pro id>' \
///       -only-testing:GeneratorRPGTests/AdventureSummaryEvaluationTests
@Suite(
    "Adventure summary evaluation",
    .tags(.evaluation),
    .serialized,
    .enabled(if: ModuleSummaryEvaluationConfiguration.isRequested(.adventure), "Set TEST_RUNNER_ADVENTURE_SUMMARY_EVAL=1 to run the evaluation")
)
struct AdventureSummaryEvaluationTests {
    static let evaluation = ModuleSummaryEvaluation(kind: .adventure, runs: ModuleSummaryEvaluationConfiguration.runs)

    @Test(
        "The on-device model titles, describes and tags the sample adventures",
        .enabled(if: ModuleSummaryEvaluationConfiguration.isModelAvailable, "Apple Intelligence is not available"),
        .evaluates(Self.evaluation, info: ["model": "on-device", "runs": "\(ModuleSummaryEvaluationConfiguration.runs)"])
    )
    func summaryQuality() {
        ModuleSummaryEvaluationConfiguration.check(Self.evaluation)
    }
}

/// Runs the Map "Extract Information" analysis on maps (rooms) with known content and judges the
/// title, description and tags:
///
///     TEST_RUNNER_MAP_SUMMARY_EVAL=1 xcodebuild test -scheme MasterRPG \
///       -destination 'platform=iOS Simulator,id=<iPhone 18 Pro id>' \
///       -only-testing:GeneratorRPGTests/MapSummaryEvaluationTests
@Suite(
    "Map summary evaluation",
    .tags(.evaluation),
    .serialized,
    .enabled(if: ModuleSummaryEvaluationConfiguration.isRequested(.map), "Set TEST_RUNNER_MAP_SUMMARY_EVAL=1 to run the evaluation")
)
struct MapSummaryEvaluationTests {
    static let evaluation = ModuleSummaryEvaluation(kind: .map, runs: ModuleSummaryEvaluationConfiguration.runs)

    @Test(
        "The on-device model titles, describes and tags the sample maps",
        .enabled(if: ModuleSummaryEvaluationConfiguration.isModelAvailable, "Apple Intelligence is not available"),
        .evaluates(Self.evaluation, info: ["model": "on-device", "runs": "\(ModuleSummaryEvaluationConfiguration.runs)"])
    )
    func summaryQuality() {
        ModuleSummaryEvaluationConfiguration.check(Self.evaluation)
    }
}

#endif
