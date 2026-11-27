// @copyright André Trettin

#if !os(tvOS)

import Evaluations
import Foundation
import FoundationModels
import TabularData
import Testing

@testable import GeneratorRPG

/// Knobs for the character evaluation, read from the environment (`TEST_RUNNER_` prefix under
/// xcodebuild).
enum CharacterSummaryEvaluationConfiguration {
    /// The evaluation calls the real on-device model and takes minutes, so it only runs on
    /// request: `TEST_RUNNER_CHARACTER_SUMMARY_EVAL=1`. The regular plans include this test target and skip it.
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["CHARACTER_SUMMARY_EVAL"] == "1"
    }

    /// How often each character is analyzed. `CHARACTER_SUMMARY_EVAL_RUNS`. Five runs (40 samples)
    /// by default: with three, one sample is about 4 %, so prompt changes drowned in the noise.
    static var runs: Int {
        Int(ProcessInfo.processInfo.environment["CHARACTER_SUMMARY_EVAL_RUNS"] ?? "").map { max($0, 1) } ?? 5
    }

    /// Share of runs that must pass every rule. `CHARACTER_SUMMARY_EVAL_THRESHOLD`
    static var passRateThreshold: Double {
        Double(ProcessInfo.processInfo.environment["CHARACTER_SUMMARY_EVAL_THRESHOLD"] ?? "")
            .map { min(max($0, 0), 1) } ?? 0.8
    }

    /// Share of runs that may fail to produce an analysis at all (guardrail, simulator safety check).
    static let inferenceFailureTolerance = 0.2

    static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }
}

/// Runs `CharacterSummaryAnalyzer`, the Character "Extract Information" analysis, on characters
/// with known content and judges the name, description and tag parts (race, occupation, player,
/// up to two traits) it produces. The results appear in Xcode's report navigator
/// under Evaluations:
///
///     TEST_RUNNER_CHARACTER_SUMMARY_EVAL=1 xcodebuild test -scheme MasterRPG \
///       -destination 'platform=iOS Simulator,id=<iPhone 18 Pro id>' \
///       -only-testing:GeneratorRPGTests/CharacterSummaryEvaluationTests
///
/// The simulator reaches the host's model, but its safety check sometimes fails with "Simulator is
/// not supported"; those runs count as inference failures up to the tolerance.
@Suite(
    "Character summary evaluation",
    .tags(.evaluation),
    .serialized,
    .enabled(if: CharacterSummaryEvaluationConfiguration.isRequested, "Set TEST_RUNNER_CHARACTER_SUMMARY_EVAL=1 to run the evaluation")
)
struct CharacterSummaryEvaluationTests {
    static let evaluation = CharacterSummaryEvaluation(runs: CharacterSummaryEvaluationConfiguration.runs)

    @Test(
        "The on-device model names, describes and tags the sample characters",
        .enabled(if: CharacterSummaryEvaluationConfiguration.isModelAvailable, "Apple Intelligence is not available"),
        .evaluates(Self.evaluation, info: ["model": "on-device", "runs": "\(CharacterSummaryEvaluationConfiguration.runs)"])
    )
    func summaryQuality() {
        let result = EvaluationContext.current.result
        let sampleCount = Double(CharacterSummarySample.dataset(runs: Self.evaluation.runs).count)
        let passRate = result.aggregateValue(.mean(of: Self.evaluation.passed))
        let nameRate = result.aggregateValue(.mean(of: Self.evaluation.nameRules))
        let playerRate = result.aggregateValue(.mean(of: Self.evaluation.playerRules))
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
            failedRuns / sampleCount <= CharacterSummaryEvaluationConfiguration.inferenceFailureTolerance,
            "\(Int(failedRuns)) of \(Int(sampleCount)) runs produced no analysis"
        )
        #expect(
            passRate >= CharacterSummaryEvaluationConfiguration.passRateThreshold,
            "\(passRate.formatted(.percent)) of runs passed (name rules \(nameRate.formatted(.percent)), description rules \(descriptionRate.formatted(.percent)), tag rules \(tagRate.formatted(.percent)), player \(playerRate.formatted(.percent)), concept recall \(recall.formatted(.percent))), needs \(CharacterSummaryEvaluationConfiguration.passRateThreshold.formatted(.percent))"
        )
    }
}

#endif
