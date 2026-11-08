// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import Evaluations
import Foundation
import FoundationModels
import RPGResourcesDebug
import TabularData
import Testing

@testable import GeneratorRPG

/// Knobs for the photo evaluation, read from the environment (`TEST_RUNNER_` prefix under
/// xcodebuild).
enum PhotoTagEvaluationConfiguration {
    /// The evaluation calls real models, takes minutes and can use the Private Cloud Compute
    /// quota, so it only runs on request: `TEST_RUNNER_PHOTO_TAG_EVAL=1`.
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PHOTO_TAG_EVAL"] == "1"
    }

    /// How often each photo and language is analyzed. `PHOTO_TAG_EVAL_RUNS`
    static var runs: Int {
        Int(ProcessInfo.processInfo.environment["PHOTO_TAG_EVAL_RUNS"] ?? "").map { max($0, 1) } ?? 3
    }

    /// Share of runs that must pass every tag rule. `PHOTO_TAG_EVAL_THRESHOLD`
    static var passRateThreshold: Double {
        Double(ProcessInfo.processInfo.environment["PHOTO_TAG_EVAL_THRESHOLD"] ?? "")
            .map { min(max($0, 0), 1) } ?? 0.8
    }

    /// Share of runs that may fail to produce an analysis at all (offline, quota, guardrail).
    static let inferenceFailureTolerance = 0.2

    static var isOnDeviceReady: Bool {
        let model = SystemLanguageModel.default
        return model.availability == .available && model.capabilities.contains(.vision)
    }

    /// Needs the `com.apple.developer.private-cloud-compute` entitlement on the test host and the
    /// `PRIVATE_CLOUD_COMPUTE_ENTITLED` condition in GeneratorRPG. Without the entitlement even
    /// reading the availability is a fatal error, so the analyzer's switch is checked first.
    static var isCloudReady: Bool {
        PhotoSummaryAnalyzer.isPrivateCloudComputeEnabled
            && PrivateCloudComputeLanguageModel().availability == .available
    }
}

/// Runs the photo tagging on both models with Apple's Evaluations framework. The results appear in
/// Xcode's report navigator under Evaluations, one entry per model, so the two can be compared and
/// the cloud fallback judged on numbers:
///
///     TEST_RUNNER_PHOTO_TAG_EVAL=1 xcodebuild test -scheme MasterRPG \
///       -destination 'platform=iOS Simulator,id=<iPhone 18 Pro id>' \
///       -only-testing:GeneratorRPGTests/PhotoTagEvaluationTests
@Suite(
    "Photo tagging evaluation",
    .tags(.evaluation),
    .serialized,
    .enabled(if: PhotoTagEvaluationConfiguration.isRequested, "Set TEST_RUNNER_PHOTO_TAG_EVAL=1 to run the evaluation")
)
struct PhotoTagEvaluationTests {
    static let onDevice = PhotoTagEvaluation(model: .onDevice, runs: PhotoTagEvaluationConfiguration.runs)
    static let privateCloud = PhotoTagEvaluation(model: .privateCloud, runs: PhotoTagEvaluationConfiguration.runs)

    @Test(
        "On-device model tags the sample photos",
        .enabled(if: PhotoTagEvaluationConfiguration.isOnDeviceReady, "The on-device model is not ready or cannot take images"),
        .evaluates(Self.onDevice, info: ["model": "on-device", "runs": "\(PhotoTagEvaluationConfiguration.runs)"])
    )
    func onDeviceTags() {
        assertQuality(of: Self.onDevice)
    }

    @Test(
        "Private Cloud Compute tags the sample photos",
        .enabled(if: PhotoTagEvaluationConfiguration.isCloudReady, "Private Cloud Compute is not available to this test host"),
        .evaluates(Self.privateCloud, info: ["model": "private-cloud-compute", "runs": "\(PhotoTagEvaluationConfiguration.runs)"])
    )
    func privateCloudTags() {
        assertQuality(of: Self.privateCloud)
    }

    /// Without a fallback decision to make, the analyzer uses the on-device model first and never
    /// reaches for the cloud, even when the cloud is allowed.
    @Test(
        "A ready on-device model is used before the cloud",
        .enabled(if: PhotoTagEvaluationConfiguration.isOnDeviceReady, "The on-device model is not ready or cannot take images")
    )
    @MainActor
    func onDeviceFirst() async throws {
        let source = try #require(ResourcesDebug.testPhotoCGImage(named: ResourcesDebug.paladinPhoto))
        let image = try #require(PhotoAnalysisImage.downsampled(source))

        let output = try await PhotoSummaryAnalyzer().analyze(image: image, cloudConsent: .allowed)

        #expect(output.model == .onDevice)
        #expect((3...5).contains(output.analysis.tags.count))
    }

    // MARK: - Assertions

    private func assertQuality(of evaluation: PhotoTagEvaluation) {
        let result = EvaluationContext.current.result
        let sampleCount = Double(PhotoTagSample.dataset(runs: evaluation.runs).count)
        let passRate = result.aggregateValue(.mean(of: evaluation.passed))
        let ruleRate = result.aggregateValue(.mean(of: evaluation.rules))
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
            failedRuns / sampleCount <= PhotoTagEvaluationConfiguration.inferenceFailureTolerance,
            "\(evaluation.name): \(Int(failedRuns)) of \(Int(sampleCount)) runs produced no analysis"
        )
        #expect(
            passRate >= PhotoTagEvaluationConfiguration.passRateThreshold,
            "\(evaluation.name): \(passRate.formatted(.percent)) of runs passed (rules \(ruleRate.formatted(.percent)), concept recall \(recall.formatted(.percent))), needs \(PhotoTagEvaluationConfiguration.passRateThreshold.formatted(.percent))"
        )
    }
}

#endif
