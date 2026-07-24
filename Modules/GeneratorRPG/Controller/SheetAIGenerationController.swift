// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation
import FoundationModels
#if os(iOS)
import UIKit
#endif

public enum SheetAIGenerationAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var isAvailable: Bool {
        self == .available
    }

    public var message: String? {
        guard case .unavailable(let message) = self else { return nil }
        return message
    }
}

public enum SheetAIGenerationError: LocalizedError, Equatable, Sendable {
    case modelUnavailable(String)
    case emptyResponse
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let message):
            message
        case .emptyResponse:
            String(localized: "AI did not generate usable sheet content.", bundle: .module)
        case .generationFailed(let message):
            message
        }
    }
}

/// Generates one transient sheet batch from an immutable CoreRPG request.
///
/// A fresh Foundation Models session is used for every request. This keeps generation
/// independent from the adventure chat transcript and lets SwiftUI task cancellation
/// implement latest-request-wins semantics safely.
public struct SheetAIGenerationController: Sendable {
    public init(maxInputCharacters: Int = 2_800, maximumResponseTokens: Int = 800) {
        self.maxInputCharacters = maxInputCharacters
        self.maximumResponseTokens = maximumResponseTokens
    }

    public let maxInputCharacters: Int
    public let maximumResponseTokens: Int

    /// Keep presentation code independent from Foundation Models while ensuring an
    /// unavailable device never exposes an AI affordance.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// The AI composer is always presented as a tab accessory on iPhone, including
    /// when the phone is in a regular horizontal size class (for example landscape).
    @MainActor public static var usesPhoneTabAccessory: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }

    public var availability: SheetAIGenerationAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable(String(localized: "This device does not support Apple Intelligence.", bundle: .module))
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(String(localized: "Enable Apple Intelligence in System Settings to generate sheet content.", bundle: .module))
        case .unavailable(.modelNotReady):
            .unavailable(String(localized: "Apple Intelligence is still preparing its language model. Try again later.", bundle: .module))
        case .unavailable(let reason):
            .unavailable(
                String(
                    localized: "Apple Intelligence is unavailable: \(String(describing: reason))",
                    bundle: .module
                )
            )
        }
    }

    public func generateDrafts(for request: SheetGenerationRequest) async throws -> [GeneratedSheetDraft] {
        try Task.checkCancellation()

        guard availability == .available else {
            throw SheetAIGenerationError.modelUnavailable(
                availability.message ?? String(localized: "Apple Intelligence is unavailable.", bundle: .module)
            )
        }

        let prompt = Self.prompt(for: request, maxCharacters: maxInputCharacters)
        let session = LanguageModelSession(instructions: Self.instructions(for: request.focus.module))
        session.prewarm()

        do {
            let response = try await session.respond(
                to: prompt,
                generating: BlockGenModel.self,
                includeSchemaInPrompt: false,
                options: GenerationOptions(maximumResponseTokens: maximumResponseTokens)
            )
            try Task.checkCancellation()

            let drafts = Self.drafts(from: response.content)
            guard !drafts.isEmpty else {
                throw SheetAIGenerationError.emptyResponse
            }
            return drafts
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SheetAIGenerationError {
            throw error
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw SheetAIGenerationError.generationFailed(
                FoundationModelsErrorHandler.handleError(error)
            )
        }
    }

    public static func drafts(from block: BlockGenModel) -> [GeneratedSheetDraft] {
        let entryDrafts = block.entries.compactMap { entry -> GeneratedSheetDraft? in
            let title = cleaned(entry.title)
            let content = cleaned(entry.content)
            guard !title.isEmpty || !content.isEmpty else { return nil }
            return GeneratedSheetDraft(title: title, content: content)
        }
        guard entryDrafts.isEmpty else { return entryDrafts }

        let title = cleaned(block.name)
        let content = cleaned(block.information)
        guard !title.isEmpty || !content.isEmpty else { return [] }
        return [GeneratedSheetDraft(title: title, content: content)]
    }

    public static func prompt(for request: SheetGenerationRequest, maxCharacters: Int = 2_800) -> String {
        let totalBudget = max(0, maxCharacters)
        guard totalBudget > 0 else { return "" }

        let userPrompt = request.prompt.isEmpty
            ? "Generate useful new content from the focused sheet content."
            : request.prompt
        let introduction = """
        Create structured RPG sheet content for module type \(request.focus.module.token).
        Return one coherent BlockGenModel. Put each selectable sheet row in its entries array.
        Keep entry titles concise and make entry content immediately useful during play.
        Preserve the language used by the game master.
        """
        let requestHeader = "\n\nGame master's request:\n"
        let focusHeader = "\n\nFocused content:\n"
        let contextHeader = "\n\nContaining sheet context:\n"
        let fixedCharacterCount = introduction.count
            + requestHeader.count
            + focusHeader.count
            + contextHeader.count
        let contentBudget = max(0, totalBudget - fixedCharacterCount)

        let requestedUserBudget = contentBudget / 5
        let requestedFocusBudget = request.focusedContent == nil
            ? min(80, max(0, contentBudget - requestedUserBudget))
            : contentBudget * 3 / 10
        let requestedContextBudget = max(
            0,
            contentBudget - requestedUserBudget - requestedFocusBudget
        )

        let limitedUserPrompt = limitedCleaned(
            userPrompt,
            maxCharacters: requestedUserBudget
        )
        let unusedUserBudget = max(0, requestedUserBudget - limitedUserPrompt.count)

        let focusedText: String
        if let focusedContent = request.focusedContent {
            focusedText = render(
                focusedContent,
                maxCharacters: requestedFocusBudget
            )
        } else {
            focusedText = limitedCleaned(
                "None. Add content to the containing sheet.",
                maxCharacters: requestedFocusBudget
            )
        }
        let unusedFocusBudget = max(0, requestedFocusBudget - focusedText.count)

        let contextText = render(
            request.sheetContext,
            maxCharacters: requestedContextBudget + unusedUserBudget + unusedFocusBudget
        )
        let combinedPrompt = introduction
            + requestHeader
            + limitedUserPrompt
            + focusHeader
            + focusedText
            + contextHeader
            + contextText

        return limitedPrefix(combinedPrompt, maxCharacters: totalBudget)
    }

    private static func instructions(for module: NetworkModules) -> String {
        """
        You help a game master create content for an RPG sheet.
        The explicit target module is \(module.token). Treat this as a generation-purpose hint.
        Use only the user request and sheet snapshots supplied in the prompt as source material.
        Do not claim that generated details already exist outside that supplied context.
        Produce BlockGenModel structured output. Prefer several focused entries when the request
        naturally contains multiple ideas, and one entry when it does not.
        Use the closest schema category for the target module: \(categoryHint(for: module)).
        """
    }

    private static func categoryHint(for module: NetworkModules) -> String {
        switch module {
        case .map, .photo, .space, .weather:
            BlockCategoryGenModel.map.rawValue
        case .table, .dice:
            BlockCategoryGenModel.table.rawValue
        case .value:
            BlockCategoryGenModel.character.rawValue
        default:
            BlockCategoryGenModel.adventure.rawValue
        }
    }

    private static func render(
        _ snapshot: SheetContentSnapshot,
        maxCharacters: Int
    ) -> String {
        guard maxCharacters > 0 else { return "" }

        var builder = SheetAIBoundedStringBuilder(maxCharacters: maxCharacters)
        var stack = [SheetAISnapshotTraversalFrame(snapshot: snapshot, depth: 0)]
        var snapshotsVisited = 0
        let snapshotVisitLimit = max(1, min(256, maxCharacters / 8))

        while !stack.isEmpty,
              builder.remainingCharacters > 0,
              snapshotsVisited < snapshotVisitLimit {
            var frame = stack.removeLast()

            if !frame.didRenderSnapshot {
                snapshotsVisited += 1
                appendSnapshot(frame.snapshot, depth: frame.depth, to: &builder)
                frame.didRenderSnapshot = true
            }

            guard builder.remainingCharacters > 0 else {
                stack.append(frame)
                break
            }

            if frame.nextChildIndex < frame.snapshot.children.count {
                let child = frame.snapshot.children[frame.nextChildIndex]
                frame.nextChildIndex += 1
                stack.append(frame)
                stack.append(
                    SheetAISnapshotTraversalFrame(
                        snapshot: child,
                        depth: frame.depth + 1
                    )
                )
            }
        }

        if !stack.isEmpty {
            builder.markTruncated()
        }

        return builder.text
    }

    private static func appendSnapshot(
        _ snapshot: SheetContentSnapshot,
        depth: Int,
        to builder: inout SheetAIBoundedStringBuilder
    ) {
        let indentation = String(repeating: "  ", count: min(depth, 6))
        appendField(
            snapshot.name,
            prefix: "\(indentation)Title: ",
            maximumValueCharacters: 160,
            to: &builder
        )
        appendField(
            snapshot.content,
            prefix: "\(indentation)Content: ",
            maximumValueCharacters: 420,
            to: &builder
        )
    }

    private static func appendField(
        _ value: String,
        prefix: String,
        maximumValueCharacters: Int,
        to builder: inout SheetAIBoundedStringBuilder
    ) {
        let separatorCharacterCount = builder.text.isEmpty ? 0 : 1
        let availableValueCharacters = max(
            0,
            builder.remainingCharacters - prefix.count - separatorCharacterCount
        )
        let valueBudget = min(maximumValueCharacters, availableValueCharacters)
        let limitedValue = limitedCleaned(value, maxCharacters: valueBudget)
        guard !limitedValue.isEmpty else { return }
        builder.appendLine(prefix + limitedValue)
    }

    private static func limitedCleaned(_ value: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }

        let leadingTrimmed = value.drop(while: { $0.isWhitespace })
        let limited = limitedPrefix(leadingTrimmed, maxCharacters: maxCharacters)
        return limited.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func limitedPrefix<S: StringProtocol>(
        _ value: S,
        maxCharacters: Int
    ) -> String {
        guard maxCharacters > 0 else { return "" }

        let boundedProbe = String(value.prefix(maxCharacters + 1))
        return FoundationModelInputLimiter.limitedText(
            boundedProbe,
            maxCharacters: maxCharacters
        )
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SheetAISnapshotTraversalFrame {
    let snapshot: SheetContentSnapshot
    let depth: Int
    var nextChildIndex = 0
    var didRenderSnapshot = false
}

private struct SheetAIBoundedStringBuilder {
    init(maxCharacters: Int) {
        self.maxCharacters = max(0, maxCharacters)
    }

    let maxCharacters: Int
    private(set) var text = ""

    var remainingCharacters: Int {
        max(0, maxCharacters - text.count)
    }

    mutating func appendLine(_ line: String) {
        guard remainingCharacters > 0 else { return }

        let value = text.isEmpty ? line : "\n" + line
        let boundedValue = String(value.prefix(remainingCharacters))
        text += boundedValue
    }

    mutating func markTruncated() {
        text = FoundationModelInputLimiter.limitedText(
            text + FoundationModelInputLimiter.truncationMarker,
            maxCharacters: maxCharacters
        )
    }
}

#endif
