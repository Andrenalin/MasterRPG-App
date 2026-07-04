// @copyright André Trettin

import SwiftUI
import FoundationModels

struct TranscriptEntryView: View {
    let generatorController: AdventureGeneratorController
    let entry: Transcript.Entry
    @State private var tokenCount: Int?

    var body: some View {
        VStack(spacing: 2) {
            entryContent

            if let tokenCount {
                Text("\(tokenCount) tokens")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: entry.isFromUser ? .trailing : .leading
                    )
                    .padding(.horizontal, 16)
            }
        }
        .task(id: entry.id) {
            tokenCount = nil
            tokenCount = await resolveTokenCount()
        }
    }

    @ViewBuilder
    private var entryContent: some View {
        switch entry {
        case .prompt(let prompt):
            if let text = prompt.segments.textContentJoined() {
                MessageBubbleView(message: ChatMessage(content: text, isFromUser: true))
                    .id(entry.id)
            }

        case .response(let response):
            if let text = response.segments.textContentJoined() {
                MessageBubbleView(message: ChatMessage(entryID: entry.id, content: text, isFromUser: false))
                    .id(entry.id)
            }

        case .toolCalls(let toolCalls):
            ForEach(Array(toolCalls.enumerated()), id: \.offset) { index, toolCall in
                MessageBubbleView(message: ChatMessage(
                    entryID: entry.id,
                    content: "🔧 Calling tool: \(toolCall.toolName)",
                    isFromUser: false
                ))
                .id("\(entry.id)-tool-\(index)")
            }

        case .toolOutput(let toolOutput):
            if let text = toolOutput.segments.textContentJoined() {
                MessageBubbleView(message: ChatMessage(
                    entryID: entry.id,
                    content: "🔧 Tool result: \(text)",
                    isFromUser: false
                ))
                .id(entry.id)
            }

        case .instructions:
            EmptyView()

        @unknown default:
            EmptyView()
        }
    }

    private func resolveTokenCount() async -> Int? {
        if case .instructions = entry {
            return nil
        }

        // Avoid repeatedly calling the tokenizer while the newest entry is still streaming.
        if generatorController.model.session.isResponding,
           generatorController.model.session.transcript.last?.id == entry.id {
            await waitForStreamingToFinish()
        }

        // Always compute tokens from the latest version of the entry in the transcript.
        let latestEntry = generatorController.model.session.transcript.first(where: { $0.id == entry.id }) ?? entry
        return await tokenCount(for: latestEntry)
    }

    private func waitForStreamingToFinish() async {
        while generatorController.model.session.isResponding, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }

        // Give the transcript a moment to publish its final segment.
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func tokenCount(for entry: Transcript.Entry) async -> Int? {
        await entry.foundationLabTokenCount()
    }
}

private extension Transcript.Entry {
    var isFromUser: Bool {
        if case .prompt = self { return true }
        return false
    }
}
