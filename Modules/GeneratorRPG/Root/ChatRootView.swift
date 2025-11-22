// @copyright André Trettin

import AndrenalinKit
import FoundationModels
import SwiftUI

struct ChatRootView: View {
    let model: GeneratorModel
    var dismissAction: (() -> Void)? = nil
    
    @Environment(GeneratorRootModel.self) private var root
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var prompt: String = "Give me some dwarven names"
    
    var body: some View {
        checkView
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
                Text("Welcome to the AI Assisent.")
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

            ToolbarItem(placement: .primaryAction) {
                Button {
                    let message = prompt
                    Task {
                        root.generatorController.request(message: message)
                    }
                    prompt = ""
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
    }
}

private extension ChatRootView {
    @ViewBuilder var checkView: some View {
        switch root.generatorController.llm.availability {
        case .available:
            contentView
        case .unavailable(let reason):
            let text = switch reason {
            case .appleIntelligenceNotEnabled:
                "Apple Intelligence is not enabled. Please enable it in Settings."
            case .deviceNotEligible:
                "This device is not eligible for Apple Intelligence. Please use a compatible device."
            case .modelNotReady:
                "The language model is not ready yet. Please try again later."
            @unknown default:
                "The language model is unavailable for an unknown reason."
            }
            ContentUnavailableView(text, systemImage: "apple.intelligence.badge.xmark")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        List(root.generatorController.model.session.transcript) { entry in
            switch entry {
                case .prompt(let prompt):
                SegmentsView(segments: prompt.segments, isUser: true)
                    .listRowSeparator(.hidden)
            case .response(let answer):
                SegmentsView(segments: answer.segments, isUser: false)
            case .instructions, .toolCalls, .toolOutput:
                    EmptyView()
            @unknown default:
                    EmptyView()
            }
        }
        .listStyle(.plain)
        .onAppear {
            root.generatorController.generate(from: model)
        }
        .safeAreaInset(edge: .bottom) {
            promptFieldView
        }
    }

    @ViewBuilder
    var promptFieldView: some View {
        HStack {
            TextField(text: $prompt, prompt: textFieldText, axis: .vertical) {
                textFieldText
            }
            .disabled(root.generatorController.model.session.isResponding)
            .labelsHidden()
            .textFieldStyle(.plain)
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.secondary, lineWidth: 1)
            }
            
            Button {
                root.generatorController.request(message: prompt)
                prompt = ""
            } label: {
                Image(systemName: "apple.intelligence")
            }
            .disabled(prompt.isEmpty || root.generatorController.model.session.isResponding)
        }
        .padding(.horizontal)
    }
    
    var textFieldText: Text {
        Text("\(Image(systemName: "questionmark.circle")) How can I help you?", bundle: .module)
    }

}

struct CharacterGenView: View {
    let value: CharacterGenModel
    let level: Int
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(value.name)
                .font(.headline)
            Text(value.information)
                .foregroundStyle(.secondary)
            
            TagItemRow(tags: value.tags)
            
            ForEach(value.entries.enumerated(), id: \.self.offset) { index, element in
                Text("**\(element.name)**: \(element.content)")
                if let subvalue = element.groupedValues.first {
                    Divider()
                    CharacterGenView(value: subvalue, level: level + 1)
                }
            }
        }
        .padding(.leading, CGFloat(level * 8))
    }
}

struct SegmentsView: View {
    let segments: [Transcript.Segment]
    let isUser: Bool
 
    @Environment(GeneratorRootModel.self) private var root
    
    var body: some View {
        VStack {
            ForEach(segments, id: \.id) { segment in
                switch segment {
                case .structure(let sturcture):
                    VStack {
                        if let value = root.generatorController.model.result {
                            CharacterGenView(value: value, level: 0)
                        }
                        Group {
                            if let value = try? CharacterGenModel(sturcture.content) {
                                CharacterGenView(value: value, level: 0)
                            } else {
                                Text(LocalizedStringKey(sturcture.description))
                            }
                        }
                            .padding(8)
                            .background(isUser ? Color.blue.opacity(0.2) : nil)
                            .cornerRadius(8)
                            .contentTransition(.interpolate)
                            .animation(.easeInOut(duration: 0.3), value: sturcture.description)
                    }
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                case .text(let text):
                    VStack {
                        Text(LocalizedStringKey(text.content))
                            .padding(8)
                            .background(isUser ? Color.blue.opacity(0.2) : nil)
                            .cornerRadius(8)
                            .contentTransition(.interpolate)
                            .animation(.easeInOut(duration: 0.3), value: text)
                    }
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(GeneratorRootModel.self) var root
    
    NavigationStack {
        if let model = root.itemController.itemSync(for: MockData.previewId) {
            ChatRootView(model: model, dismissAction: nil)
        }
    }
}
