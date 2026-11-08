// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import Evaluations
import Foundation
import FoundationModels
import RPGResourcesDebug

@testable import GeneratorRPG

/// One photo to analyze, in one output language, with the tags it should get.
///
/// `ExpectedValue` is the analysis type because the framework compares a sample's expected value
/// with the subject's value; there is no golden answer here, only `expectations` (concept groups
/// as in the PDF evaluation), so `expected` stays `nil`.
struct PhotoTagSample: ModelSampleProtocol {
    typealias ExpectedValue = PhotoSummaryAnalysis
    typealias Expectation = PdfTagExpectation

    /// Name in the `RPGResourcesDebug` test photo catalog.
    let imageName: String
    let outputLanguage: String
    /// Distinguishes the repeated runs of one photo, which the framework treats as separate samples.
    let runIndex: Int
    let tagExpectation: PdfTagExpectation

    var input: ModelSampleInput {
        ModelSampleInput(prompt: Prompt("Photo \(imageName) in \(outputLanguage), run \(runIndex + 1)"))
    }

    var output: ModelSampleOutput<PhotoSummaryAnalysis, PdfTagExpectation> {
        ModelSampleOutput(expectations: tagExpectation)
    }

    var expected: PhotoSummaryAnalysis? { nil }
}

extension PhotoTagSample {
    /// Photos from the debug resources, each with its expected concepts in English and German.
    /// A concept is matched when any of its terms is inside any tag.
    static func dataset(runs: Int) -> [PhotoTagSample] {
        let photos: [(name: String, english: PdfTagExpectation, german: PdfTagExpectation)] = [
            (
                ResourcesDebug.adventurePhoto,
                PdfTagExpectation(
                    conceptGroups: [
                        ["landscape", "scenery", "environment", "scene", "painting", "concept art"],
                        ["cliff", "rock", "island", "floating", "mountain", "airship", "ship", "tower"]
                    ]
                ),
                PdfTagExpectation(
                    conceptGroups: [
                        ["landschaft", "szene", "szenerie", "umgebung", "gemälde", "konzeptkunst"],
                        ["klippe", "fels", "insel", "schwebend", "berg", "luftschiff", "schiff", "turm"]
                    ],
                    forbiddenTerms: ["landscape", "airship", "cliff", "island"]
                )
            ),
            (
                ResourcesDebug.paladinPhoto,
                PdfTagExpectation(
                    conceptGroups: [
                        ["portrait", "character", "figure", "hero"],
                        ["paladin", "knight", "cleric", "priest", "templar", "crusader", "warrior"],
                        ["armor", "armour", "book", "cross", "holy", "white"]
                    ],
                    minimumMatchedGroups: 2
                ),
                PdfTagExpectation(
                    conceptGroups: [
                        ["porträt", "charakter", "figur", "held"],
                        ["paladin", "ritter", "kleriker", "priester", "templer", "kreuzritter", "krieger"],
                        ["rüstung", "buch", "kreuz", "heilig", "weiß"]
                    ],
                    minimumMatchedGroups: 2,
                    forbiddenTerms: ["knight", "portrait", "armor", "cleric"]
                )
            ),
            (
                ResourcesDebug.wizardPhoto,
                PdfTagExpectation(
                    conceptGroups: [
                        ["portrait", "character", "figure"],
                        ["wizard", "mage", "sorcerer", "warlock", "hooded", "cloak", "robe"],
                        ["magic", "spell", "lightning", "energy", "glow", "arcane"]
                    ],
                    minimumMatchedGroups: 2
                ),
                PdfTagExpectation(
                    conceptGroups: [
                        ["porträt", "charakter", "figur"],
                        ["zauberer", "magier", "hexer", "kapuze", "umhang", "robe", "mantel"],
                        ["magie", "zauber", "blitz", "energie", "leuchten", "arkan"]
                    ],
                    minimumMatchedGroups: 2,
                    forbiddenTerms: ["wizard", "portrait", "magic", "lightning", "hooded"]
                )
            )
        ]

        return (0..<runs).flatMap { run in
            photos.flatMap { photo in
                [
                    PhotoTagSample(imageName: photo.name, outputLanguage: "English", runIndex: run, tagExpectation: photo.english),
                    PhotoTagSample(imageName: photo.name, outputLanguage: "German", runIndex: run, tagExpectation: photo.german)
                ]
            }
        }
    }
}

/// Scores the tags `PhotoSummaryAnalyzer` produces for the sample photos with one model.
///
/// The tag rules are the ones of the PDF evaluation (`PdfTagEvaluator`): 3 to 5 tags, none empty,
/// duplicated, generic or written as a label, plus the expected concepts. Photos add their own
/// generic words ("image", "illustration").
struct PhotoTagEvaluation: Evaluation {
    typealias Sample = PhotoTagSample
    typealias Subject = ModelSubject<PhotoSummaryAnalysis>

    let model: PhotoAnalysisModel
    let runs: Int

    /// Share of runs that pass every rule and find the expected concepts.
    let passed = Metric("TagsPass")
    /// Share of runs that break no tag rule, ignoring the concepts.
    let rules = Metric("TagRules")
    /// How much of the required concepts the tags found, 0...1.
    let concepts = Metric("ConceptRecall")

    var name: String { "Photo tags, \(model == .onDevice ? "on-device" : "Private Cloud Compute")" }

    var dataset: ArrayLoader<PhotoTagSample> {
        ArrayLoader(samples: PhotoTagSample.dataset(runs: runs))
    }

    nonisolated(nonsending)
    func subject(from sample: PhotoTagSample) async throws -> ModelSubject<PhotoSummaryAnalysis> {
        let image = try await Self.image(named: sample.imageName)
        let analysis = try await PhotoSummaryAnalyzer().analyze(
            image: image,
            outputLanguage: sample.outputLanguage,
            using: model
        )
        return ModelSubject(value: analysis)
    }

    var evaluators: Evaluators {
        Evaluator<PhotoTagSample> { [passed] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            return result.passed ? passed.passing() : passed.failing(rationale: Self.rationale(result))
        }
        Evaluator<PhotoTagSample> { [rules] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            let ruleViolations = result.violations.filter { !$0.hasPrefix("matched ") }
            return ruleViolations.isEmpty ? rules.passing() : rules.failing(rationale: ruleViolations.joined(separator: "; "))
        }
        Evaluator<PhotoTagSample> { [concepts] sample, subject in
            let result = Self.evaluate(subject.value, for: sample)
            let required = Double(max(result.requiredGroupCount, 1))
            return concepts.scoring(
                min(Double(result.matchedGroups.count) / required, 1),
                rationale: "tags: \(result.tags.joined(separator: ", "))"
            )
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: passed)
        aggregator.computeMean(of: rules)
        aggregator.computeMean(of: concepts)
    }

    // MARK: - Helpers

    static func evaluate(_ analysis: PhotoSummaryAnalysis, for sample: PhotoTagSample) -> PdfTagEvaluation {
        var evaluator = PdfTagEvaluator()
        evaluator.genericTags.formUnion(["image", "photo", "picture", "illustration", "artwork", "art", "bild", "foto", "grafik", "kunst", "kunstwerk", "illustration"])
        return evaluator.evaluate(tags: analysis.tags, title: analysis.title, expectation: sample.tagExpectation)
    }

    static func rationale(_ result: PdfTagEvaluation) -> String {
        "tags: \(result.tags.joined(separator: ", ")); " + result.violations.joined(separator: "; ")
    }

    private static func image(named name: String) async throws -> CGImage {
        let source = await MainActor.run { ResourcesDebug.testPhotoCGImage(named: name) }
        guard let source, let image = PhotoAnalysisImage.downsampled(source) else {
            throw PhotoSummaryAnalysisError.imageUnavailable
        }
        return image
    }
}

#endif
