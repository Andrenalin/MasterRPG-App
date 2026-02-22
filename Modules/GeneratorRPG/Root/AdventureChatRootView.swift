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
    
    @State private var prompt: String = "Eine Zwergenfestung für Elfen erbaut, hat 7 verschieden farbige Räume. Was könnten sie bedeuten?"
    
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
        List(model.session.transcript) { entry in
            switch entry {
                case .prompt(let prompt):
                ChatSegmentsView(segments: prompt.segments, isUser: true)
                    .listRowSeparator(.hidden)
            case .response(let answer):
                ChatSegmentsView(segments: answer.segments, isUser: false)
            case .instructions, .toolCalls, .toolOutput:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
        .listStyle(.plain)
        .overlay {
            if !model.responseErrorContent.isEmpty {
                Text(model.responseErrorContent)
                Button {
                    model.responseErrorContent = ""
                } label: {
                    Text("Understand", bundle: .module)
                }
            }
        }
        .onAppear {
            root.generatorController.generate()
        }
        .safeAreaInset(edge: .bottom) {
            promptFieldView
        }
    }

    @ViewBuilder var promptFieldView: some View {
        HStack {
            TextField(text: $prompt, prompt: textFieldText, axis: .vertical) {
                textFieldText
            }
            .disabled(model.session.isResponding)
            .labelsHidden()
            .textFieldStyle(.plain)
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.secondary, lineWidth: 1)
            }
            
            Button {
                generatorController.request(message: prompt)
                prompt = ""
            } label: {
                Image(systemName: root.config.module.icon)
            }
            .disabled(prompt.isEmpty || model.session.isResponding)
        }
        .padding(.horizontal)
    }
    
    var textFieldText: Text {
        Text("\(Image(systemName: "questionmark.circle")) How can I help you?", bundle: .module)
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
