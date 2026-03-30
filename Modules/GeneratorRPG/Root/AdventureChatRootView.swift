// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

struct AdventureChatRootView: View {
    let sheetModel: SheetModel
    var dismissAction: (() -> Void)? = nil
    
    @Environment(GeneratorRootModel.self) private var root
    
    private var model: AdventureSessionModel {
        generatorController.model
    }

    private var generatorController: AdventureGeneratorController {
        root.adventureGeneratorController
    }

    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel = ChatViewModel()
    @State private var scrollID: String?
    
    @State private var prompt: String = "Eine Zwergenfestung für Elfen erbaut, hat 7 verschieden farbige Räume. Was könnten sie bedeuten?"
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        FoundationBasicView {
            contentView
        }
        .padding(.bottom)
        .environment(\.colorScheme, colorScheme)
#if os(macOS) || os(visionOS)
        .padding(.top)
#else
        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
#if os(visionOS)
        .glassBackgroundEffect()
#endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Welcome to the AI Assistant", bundle: .module)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if let dismissAction {
                        dismissAction()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

private extension AdventureChatRootView {
    @ViewBuilder private var contentView: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TokenUsageBar(currentTokenCount: model.currentTokenCount, maxContextSize: model.maxContextSize, tokenUsageFraction: model.tokenUsageFraction)

            messagesView

            ChatInputView(messageText: $prompt, generatorController: generatorController, isTextFieldFocused: $isTextFieldFocused)
        }
        .environment(viewModel)
        .alert(
            "Error",
            isPresented: $model.showError,
            actions: { Button("OK") { viewModel.dismissError() } },
            message: { Text(viewModel.errorMessage ?? "") }
        )
        .task {
            await generatorController.generate()
            try? await Task.sleep(for: .seconds(0.5))
            isTextFieldFocused = true
        }
        .onDisappear {
            generatorController.tearDown()
        }
    }
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isChatEffectivelyEmpty {
                        Text("How can we help you today?")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 48)
                    }

                    ForEach(model.session.transcript) { entry in
                        TranscriptEntryView(generatorController: generatorController, entry: entry)
                            .id(entry.id)
                    }

                    if model.isSummarizing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Summarizing conversation...")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("summarizing")
                    }

                    if model.isApplyingWindow {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Optimizing conversation history...")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("windowing")
                    }

                    // Empty spacer for bottom padding
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical)
            }
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .scrollPosition(id: $scrollID, anchor: .bottom)
            .onChange(of: model.session.transcript.count) { _, _ in
                if let lastEntry = model.session.transcript.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.isSummarizing) { _, isSummarizing in
                if isSummarizing {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("summarizing", anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.isApplyingWindow) { _, isApplyingWindow in
                if isApplyingWindow {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("windowing", anchor: .bottom)
                    }
                }
            }
        }
        .defaultScrollAnchor(.bottom)
    }

    private var isChatEffectivelyEmpty: Bool {
        !model.session.transcript.contains { entry in
            switch entry {
            case .instructions:
                return false
            default:
                return true
            }
        }
    }

    private func clearChat() {
        prompt = ""
        scrollID = "bottom"
        generatorController.clearChat()
    }

}

#Preview(traits: .mockData) {
    @Previewable @Environment(GeneratorRootModel.self) var root
    
    NavigationStack {
        AdventureChatRootView(sheetModel: .empty, dismissAction: nil)
    }
}

struct ChatSegmentsView: View {
    let segments: [Transcript.Segment]
    let isUser: Bool
 
    @Environment(GeneratorRootModel.self) private var root
    
    var body: some View {
        VStack {
            ForEach(segments, id: \.id) { segment in
                switch segment {
                case .structure(let sturcture):
                    VStack {
                        Text(LocalizedStringKey(sturcture.description))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(isUser ? Color.blue.opacity(0.2) : nil)
                    .clipShape(.rect(cornerRadius: 8))
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.3), value: sturcture.description)
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                case .text(let text):
                    VStack {
                        Text(LocalizedStringKey(text.content))
                            .padding(8)
                            .background(isUser ? Color.blue.opacity(0.2) : nil)
                            .clipShape(.rect(cornerRadius: 8))
                            .contentTransition(.interpolate)
                            .animation(.easeInOut(duration: 0.3), value: text)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .textSelection(.enabled)
    }
}
