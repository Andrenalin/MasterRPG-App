// @copyright André Trettin

#if !os(tvOS)

import Evaluations
import Foundation
import FoundationModels

@testable import GeneratorRPG

/// One character, analyzed once, with what the result should contain. As in
/// `TableSummarySample` there is no golden answer, only `expectations`, so `expected` stays `nil`.
struct CharacterSummarySample: ModelSampleProtocol {
    typealias ExpectedValue = CharacterSummaryAnalysis
    typealias Expectation = CharacterSummaryExpectation

    let fixture: CharacterSummaryFixture
    /// Distinguishes the repeated runs of one character, which the framework treats as separate samples.
    let runIndex: Int

    var input: ModelSampleInput {
        ModelSampleInput(prompt: Prompt("Character \(fixture.testDescription), run \(runIndex + 1)"))
    }

    var output: ModelSampleOutput<CharacterSummaryAnalysis, CharacterSummaryExpectation> {
        ModelSampleOutput(expectations: fixture.expectation)
    }

    var expected: CharacterSummaryAnalysis? { nil }
}

extension CharacterSummarySample {
    static func dataset(runs: Int) -> [CharacterSummarySample] {
        (0..<runs).flatMap { run in
            CharacterSummaryEvaluationConfiguration.fixtures.map { CharacterSummarySample(fixture: $0, runIndex: run) }
        }
    }
}

/// Scores the name, description and tag parts `CharacterSummaryAnalyzer` produces for the sample
/// characters, the analysis behind the Character "Extract Information". The rules are in
/// `CharacterSummaryEvaluator`.
struct CharacterSummaryEvaluation: Evaluation {
    typealias Sample = CharacterSummarySample
    typealias Subject = ModelSubject<CharacterSummaryAnalysis>

    let runs: Int

    /// Share of runs that pass every rule and find the expected concepts.
    let passed = Metric("CharacterSummaryPass")
    /// Share of runs whose name breaks no rule (kept when given, a real name when invented).
    let nameRules = Metric("CharacterNameRules")
    /// Share of runs whose description breaks no rule.
    let descriptionRules = Metric("CharacterDescriptionRules")
    /// Share of runs whose race, occupation, traits, player's name and tag count break no rule.
    let tagRules = Metric("CharacterTagRules")
    /// Share of runs with the player's name right: present when the sheet names one, absent when not.
    let playerRules = Metric("CharacterPlayerRules")
    /// How much of the expected race, occupation, trait and description concepts were found, 0...1.
    let concepts = Metric("CharacterConceptRecall")

    var name: String { "Character summary" }

    var dataset: ArrayLoader<CharacterSummarySample> {
        ArrayLoader(samples: CharacterSummarySample.dataset(runs: runs))
    }

    nonisolated(nonsending)
    func subject(from sample: CharacterSummarySample) async throws -> ModelSubject<CharacterSummaryAnalysis> {
        let resultModel = await MainActor.run { TableSummaryAnalyzerResultModel() }
        let analysis = try await CharacterSummaryAnalyzer().analyzeCharacter(
            sheetText: sample.fixture.entriesText,
            characterName: sample.fixture.characterName,
            resultModel: resultModel,
            outputLanguage: sample.fixture.outputLanguage
        )
        return ModelSubject(value: analysis)
    }

    var evaluators: Evaluators {
        Evaluator<CharacterSummarySample> { [passed] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            if result.passed, CharacterSummaryEvaluationConfiguration.showsAllSamples {
                print("passed sample: \(Self.rationale(result))")
            }
            return result.passed ? passed.passing() : passed.failing(rationale: Self.rationale(result))
        }
        Evaluator<CharacterSummarySample> { [nameRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.nameRuleViolations.isEmpty
                ? nameRules.passing()
                : nameRules.failing(rationale: result.nameRuleViolations.joined(separator: "; "))
        }
        Evaluator<CharacterSummarySample> { [descriptionRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.descriptionRuleViolations.isEmpty
                ? descriptionRules.passing()
                : descriptionRules.failing(rationale: "description: \(result.analysis.description); " + result.descriptionRuleViolations.joined(separator: "; "))
        }
        Evaluator<CharacterSummarySample> { [tagRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.tagRuleViolations.isEmpty
                ? tagRules.passing()
                : tagRules.failing(rationale: "tags: \(result.tags.joined(separator: ", ")); " + result.tagRuleViolations.joined(separator: "; "))
        }
        Evaluator<CharacterSummarySample> { [playerRules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.playerViolations.isEmpty
                ? playerRules.passing()
                : playerRules.failing(rationale: result.playerViolations.joined(separator: "; "))
        }
        Evaluator<CharacterSummarySample> { [concepts] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return concepts.scoring(result.conceptScore, rationale: "tags: \(result.tags.joined(separator: ", "))")
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: passed)
        aggregator.computeMean(of: nameRules)
        aggregator.computeMean(of: descriptionRules)
        aggregator.computeMean(of: tagRules)
        aggregator.computeMean(of: playerRules)
        aggregator.computeMean(of: concepts)
    }

    // MARK: - Helpers

    static func evaluate(_ analysis: CharacterSummaryAnalysis, for sample: CharacterSummarySample) -> CharacterSummaryVerdict {
        CharacterSummaryEvaluator().evaluate(
            analysis,
            existingName: sample.fixture.characterName,
            expectation: sample.fixture.expectation
        )
    }

    static func rationale(_ result: CharacterSummaryVerdict) -> String {
        let analysis = result.analysis
        return "name: \(analysis.name); race: \(analysis.race); occupation: \(analysis.occupation); player: \(analysis.playerName); "
            + "traits: \(analysis.traits.joined(separator: ", ")); description: \(analysis.description); "
            + result.violations.joined(separator: "; ")
    }
}

#endif
