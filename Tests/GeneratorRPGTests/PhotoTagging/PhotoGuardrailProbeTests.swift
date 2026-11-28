// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import Foundation
import FoundationModels
import RPGResourcesDebug
import Testing

@testable import GeneratorRPG

/// Neutral schema for the probe: the guide texts are part of the prompt, so they carry no RPG or
/// tag-rule wording that could itself trip a guardrail.
@Generable(description: "Title, description and keywords of a fantasy picture")
struct ProbePhotoAnalysis {
    @Guide(description: "A short title for the main subject")
    var title: String

    @Guide(description: "What is visible, in 2 to 3 sentences")
    var summary: String

    @Guide(description: "3 to 5 short keywords", .count(3...5))
    var tags: [String]
}

/// One way of asking the on-device model for a photo's title, description and tags.
struct PhotoPromptVariant: Sendable {
    enum Output: Sendable {
        /// `PhotoSummaryAnalyzer` as shipped.
        case analyzer
        /// Guided generation of `ProbePhotoAnalysis`.
        case generable
        /// A `String` in "Title:/Description:/Tags:" lines, default guardrails.
        case text
        /// The same lines with `.permissiveContentTransformations`, which only skips the
        /// guardrails for `String` responses.
        case permissiveText
    }

    let name: String
    let output: Output
    var useCase: SystemLanguageModel.UseCase = .general
    var instructions: (@Sendable (String) -> String)?
    var prompt: @Sendable (String) -> String = { _ in "" }
}

enum PhotoProbeOutcome: Sendable {
    case analysis(title: String, summary: String, tags: [String])
    case blocked(String)
    case refused(String)
    case failed(String)

    var label: String {
        switch self {
        case .analysis: "OK"
        case .blocked: "GUARDRAIL"
        case .refused: "REFUSAL"
        case .failed: "ERROR"
        }
    }
}

/// Finds a prompt the on-device guardrails let through for character portraits, whose description
/// and tags feed `CharacterSummaryAnalyzer`. Prints one line per call and a table per variant; it
/// asserts nothing.
///
///     TEST_RUNNER_PHOTO_GUARDRAIL_PROBE=1 TEST_RUNNER_PHOTO_GUARDRAIL_PROBE_VARIANTS=baseline,character \
///       xcodebuild test ... -only-testing:GeneratorRPGTests/PhotoGuardrailProbeTests
@Suite(
    "Photo guardrail probe",
    .tags(.evaluation),
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["PHOTO_GUARDRAIL_PROBE"] == "1", "Set TEST_RUNNER_PHOTO_GUARDRAIL_PROBE=1 to run the probe")
)
struct PhotoGuardrailProbeTests {

    static let photos = [
        ResourcesDebug.adventurePhoto,
        ResourcesDebug.paladinPhoto,
        ResourcesDebug.wizardPhoto,
        ResourcesDebug.dwarfPhoto,
        ResourcesDebug.drunkenPiratePhoto,
        ResourcesDebug.pirateCaptainPhoto
    ]

    static var languages: [String] {
        (ProcessInfo.processInfo.environment["PHOTO_GUARDRAIL_PROBE_LANGUAGES"] ?? "English,German")
            .split(separator: ",").map(String.init)
    }

    static var runs: Int {
        Int(ProcessInfo.processInfo.environment["PHOTO_GUARDRAIL_PROBE_RUNS"] ?? "").map { max($0, 1) } ?? 1
    }

    static var selectedVariants: [PhotoPromptVariant] {
        guard let names = ProcessInfo.processInfo.environment["PHOTO_GUARDRAIL_PROBE_VARIANTS"] else {
            return PhotoPromptVariants.all
        }
        let wanted = Set(names.split(separator: ",").map(String.init))
        return PhotoPromptVariants.all.filter { wanted.contains($0.name) }
    }

    @Test("Prompt variants against the guardrails")
    @MainActor
    func probe() async throws {
        let images = try Self.photos.map { name in
            let source = try #require(ResourcesDebug.testPhotoCGImage(named: name))
            return (name, try #require(PhotoAnalysisImage.downsampled(source)))
        }
        var table: [String] = []
        for variant in Self.selectedVariants {
            var passed = 0
            var total = 0
            var perPhoto: [String] = []
            for (name, image) in images {
                for language in Self.languages {
                    var cell = 0
                    for run in 0..<Self.runs {
                        let outcome = await Self.run(variant, image: image, language: language)
                        total += 1
                        if case .analysis = outcome {
                            passed += 1
                            cell += 1
                        }
                        print("PROBE [\(variant.name)] \(name) \(language) #\(run + 1): \(outcome.label) \(Self.detail(outcome))")
                    }
                    perPhoto.append("\(name)/\(language.prefix(2)) \(cell)/\(Self.runs)")
                }
            }
            table.append("PROBE RESULT [\(variant.name)] \(passed)/\(total) — \(perPhoto.joined(separator: ", "))")
        }
        print(table.joined(separator: "\n"))
    }

    // MARK: - Running one variant

    static func run(_ variant: PhotoPromptVariant, image: CGImage, language: String) async -> PhotoProbeOutcome {
        do {
            switch variant.output {
            case .analyzer:
                let analysis = try await PhotoSummaryAnalyzer().analyze(image: image, outputLanguage: language, using: .onDevice)
                return .analysis(title: analysis.title, summary: analysis.summary, tags: analysis.tags)
            case .generable:
                let session = session(for: variant, guardrails: .default, language: language)
                let response = try await session.respond(generating: ProbePhotoAnalysis.self) {
                    variant.prompt(language)
                    Attachment(image)
                }
                let content = response.content
                return .analysis(title: content.title, summary: content.summary, tags: content.tags)
            case .text, .permissiveText:
                let guardrails: SystemLanguageModel.Guardrails = variant.output == .permissiveText ? .permissiveContentTransformations : .default
                let session = session(for: variant, guardrails: guardrails, language: language)
                let response = try await session.respond {
                    variant.prompt(language)
                    Attachment(image)
                }
                return parsedLines(response.content)
            }
        } catch let error as LanguageModelError {
            switch error {
            case .guardrailViolation(let violation):
                return .blocked("\(violation.debugDescription) \(violation.metadata)")
            case .refusal:
                return .refused(String(describing: error))
            default:
                return .failed(String(describing: error))
            }
        } catch {
            return .failed(String(describing: error))
        }
    }

    private static func session(
        for variant: PhotoPromptVariant,
        guardrails: SystemLanguageModel.Guardrails,
        language: String
    ) -> LanguageModelSession {
        let model = SystemLanguageModel(useCase: variant.useCase, guardrails: guardrails)
        if let instructions = variant.instructions?(language) {
            return LanguageModelSession(model: model, instructions: instructions)
        }
        return LanguageModelSession(model: model)
    }

    /// Reads "Title: …", "Description: …" and "Tags: a, b, c" lines (in any language the labels
    /// stay English because the prompt says so). Text without them is a refusal message.
    static func parsedLines(_ text: String) -> PhotoProbeOutcome {
        var title = ""
        var summary = ""
        var tags: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces).replacing("**", with: "")
            if let value = value(of: trimmed, label: "Title") {
                title = value
            } else if let value = value(of: trimmed, label: "Description") {
                summary = value
            } else if let value = value(of: trimmed, label: "Tags") {
                tags = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }
        guard !summary.isEmpty, !tags.isEmpty else {
            return .refused(text.replacing("\n", with: " ⏎ "))
        }
        return .analysis(title: title, summary: summary, tags: tags)
    }

    private static func value(of line: String, label: String) -> String? {
        let prefix = "\(label):"
        guard line.lowercased().hasPrefix(prefix.lowercased()) else {
            return nil
        }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func detail(_ outcome: PhotoProbeOutcome) -> String {
        switch outcome {
        case let .analysis(title, summary, tags):
            "| \(title) | \(tags.joined(separator: ", ")) | \(summary)"
        case let .blocked(text), let .refused(text), let .failed(text):
            "| \(text.prefix(400))"
        }
    }
}

// MARK: - Variants

enum PhotoPromptVariants {
    static let lineFormat = """
    Answer in exactly three lines and keep the labels Title, Description and Tags in English:
    Title: <short title>
    Description: <2 to 3 sentences>
    Tags: <3 to 5 keywords, separated by commas>
    """

    static let characterInstructions = """
    You write catalogue entries for fantasy artwork: painted or drawn pictures of fictional \
    characters, creatures, places and items from fantasy stories. When the picture shows a figure, \
    describe it as a fictional character: its fantasy folk (for example human, dwarf, elf, orc), \
    its apparent role or profession, its clothing, equipment and the setting. Describe only what is \
    visible, neutrally and without judging. Do not invent names.
    """

    static let all: [PhotoPromptVariant] = [
        PhotoPromptVariant(name: "baseline", output: .analyzer),
        PhotoPromptVariant(
            name: "describe",
            output: .text,
            prompt: { language in "Describe this picture in 2 sentences, in \(language)." }
        ),
        PhotoPromptVariant(
            name: "neutral",
            output: .generable,
            instructions: { _ in
                "You write short catalogue entries for pictures in a fantasy art collection. Describe only what is visible, factually and neutrally."
            },
            prompt: { language in
                "Write a title, a description in 2 to 3 sentences and 3 to 5 keywords for this picture. Write everything in \(language)."
            }
        ),
        PhotoPromptVariant(
            name: "character",
            output: .generable,
            instructions: { _ in characterInstructions },
            prompt: { language in
                "Write a title, a description in 2 to 3 sentences and 3 to 5 keywords for this picture. Write everything in \(language)."
            }
        ),
        PhotoPromptVariant(
            name: "characterText",
            output: .text,
            instructions: { _ in characterInstructions },
            prompt: { language in
                "Write a title, a description in 2 to 3 sentences and 3 to 5 keywords for this picture, in \(language).\n\(lineFormat)"
            }
        ),
        PhotoPromptVariant(
            name: "characterPermissive",
            output: .permissiveText,
            instructions: { _ in characterInstructions },
            prompt: { language in
                "Write a title, a description in 2 to 3 sentences and 3 to 5 keywords for this picture, in \(language).\n\(lineFormat)"
            }
        ),
        PhotoPromptVariant(
            name: "contentTagging",
            output: .generable,
            useCase: .contentTagging,
            instructions: { _ in characterInstructions },
            prompt: { language in
                "Write a title, a description in 2 to 3 sentences and 3 to 5 keywords for this picture. Write everything in \(language)."
            }
        )
    ]
}

#endif
