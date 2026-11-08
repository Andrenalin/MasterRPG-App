// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels
import PDFKit
import Testing

@testable import GeneratorRPG

extension Tag {
    /// Tests that call the real on-device model. Their output is non-deterministic, so they check
    /// a pass rate and are not part of the regular test plans.
    @Tag static var evaluation: Self
}

/// Knobs for the evaluation, read from the environment (`TEST_RUNNER_` prefix under xcodebuild).
enum PdfTagEvaluationConfiguration {
    /// How often each fixture is analyzed. `PDF_TAG_EVAL_RUNS`
    static var runs: Int {
        Int(ProcessInfo.processInfo.environment["PDF_TAG_EVAL_RUNS"] ?? "").map { max($0, 1) } ?? 5
    }

    /// Share of runs that must pass the rules for a fixture to pass. `PDF_TAG_EVAL_THRESHOLD`
    static var passRateThreshold: Double {
        Double(ProcessInfo.processInfo.environment["PDF_TAG_EVAL_THRESHOLD"] ?? "")
            .map { min(max($0, 0), 1) } ?? 0.8
    }

    /// The suite takes minutes and needs the model, so it only runs on request:
    /// `TEST_RUNNER_PDF_TAG_EVAL=1`. The regular plans include this test target and skip it.
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PDF_TAG_EVAL"] == "1"
    }

    static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }
}

/// Runs `PdfSummaryAnalyzer` on documents with known content and judges the tags it produces.
///
/// Every fixture is analyzed several times, because a single generation can be good or bad by
/// chance. A run passes when it breaks no rule and finds enough of the expected concepts; the
/// fixture passes when enough runs do. Run it on request, on a device or simulator with Apple Intelligence
/// (the simulator reaches the host's model but its safety check sometimes fails with "Simulator is
/// not supported"):
///
///     TEST_RUNNER_PDF_TAG_EVAL=1 xcodebuild test -scheme MasterRPG \
///       -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
///       -only-testing:GeneratorRPGTests/PdfTagEvaluationTests
@Suite(
    "PDF tagging evaluation",
    .tags(.evaluation),
    .serialized,
    .enabled(if: PdfTagEvaluationConfiguration.isRequested, "Set TEST_RUNNER_PDF_TAG_EVAL=1 to run the evaluation"),
    .enabled(if: PdfTagEvaluationConfiguration.isModelAvailable, "Apple Intelligence is not available")
)
@MainActor
struct PdfTagEvaluationTests {
    private let evaluator = PdfTagEvaluator()

    @Test("Generated fixture gets fitting tags", arguments: PdfTagFixture.generated)
    func generatedFixture(_ fixture: PdfTagFixture) async throws {
        try await evaluate(fixture)
    }

    @Test("Bundled real PDF gets fitting tags", arguments: PdfTagFixture.bundled)
    func bundledFixture(_ fixture: PdfTagFixture) async throws {
        try await evaluate(fixture)
    }

    // MARK: - Running

    private func evaluate(_ fixture: PdfTagFixture) async throws {
        let runs = PdfTagEvaluationConfiguration.runs
        let threshold = PdfTagEvaluationConfiguration.passRateThreshold
        let document = try fixture.makeDocument()

        var outcomes: [Outcome] = []
        for _ in 0..<runs {
            outcomes.append(await analyze(document, fixture: fixture))
        }

        let report = Report(fixture: fixture, outcomes: outcomes, threshold: threshold)
        print(report.text)
        Attachment.record(report.text, named: "\(fixture.name) tags.txt")

        #expect(
            report.passRate >= threshold,
            "\(fixture.name): \(report.passedCount)/\(runs) runs passed, needs \(threshold.formatted(.percent)).\n\(report.text)"
        )
    }

    private func analyze(_ document: PDFDocument, fixture: PdfTagFixture) async -> Outcome {
        do {
            let analysis = try await PdfSummaryAnalyzer().analyzeWithProgress(
                from: document,
                resultModel: PdfSummaryAnalyzerResultModel(),
                outputLanguage: fixture.outputLanguage
            )
            return .evaluated(
                evaluator.evaluate(tags: analysis.tags, title: analysis.title, expectation: fixture.expectation)
            )
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - Report

private extension PdfTagEvaluationTests {
    enum Outcome {
        case evaluated(PdfTagEvaluation)
        /// The analyzer threw, for example a guardrail violation. Counts as a failed run.
        case failed(String)

        var passed: Bool {
            if case .evaluated(let evaluation) = self { evaluation.passed } else { false }
        }
    }

    struct Report {
        let fixture: PdfTagFixture
        let outcomes: [Outcome]
        let threshold: Double

        var passedCount: Int { outcomes.filter(\.passed).count }
        var passRate: Double { Double(passedCount) / Double(outcomes.count) }

        var text: String {
            var lines = [
                "PDF tagging: \(fixture.testDescription) - \(passedCount)/\(outcomes.count) runs passed"
            ]
            for (index, outcome) in outcomes.enumerated() {
                switch outcome {
                case .evaluated(let evaluation):
                    let status = evaluation.passed ? "pass" : "FAIL"
                    let recall = evaluation.recall.formatted(.percent.precision(.fractionLength(0)))
                    lines.append("  run \(index + 1) \(status), recall \(recall): \(evaluation.tags.joined(separator: ", "))")
                    lines.append(contentsOf: evaluation.violations.map { "    - \($0)" })
                case .failed(let message):
                    lines.append("  run \(index + 1) FAIL: analyzer error: \(message)")
                }
            }
            return lines.joined(separator: "\n")
        }
    }
}

#endif
