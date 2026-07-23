// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

struct AdventureGenRootView: View {
    let model: GeneratorModel
    var dismissAction: (() -> Void)? = nil
    
    @Environment(GeneratorRootModel.self) private var root
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var prompt = String(
        localized: "Create a new campaign for DungeonSlayer under the mountain in an old deserted dwarven empire.",
        bundle: .module
    )
//    @State private var prompt: String = "Erstelle ein Zwergenkampagne unter dem Berg in einem verlassenen, alten Königreich."
    
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
                Text("Welcome to the AI Assistant.", bundle: .module)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(
                    LocalizedStringResource("Done", bundle: .module),
                    systemImage: "checkmark"
                ) {
                    if let dismissAction {
                        dismissAction()
                    } else {
                        dismiss()
                    }
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(
                    LocalizedStringResource("Generate adventure", bundle: .module),
                    systemImage: "gear"
                ) {
                    let message = prompt
                    Task {
                        await root.generatorController.requestAdventure(message: message)
                    }
                    prompt = ""
                }
                .labelStyle(.iconOnly)
            }
        }
    }
}

private extension AdventureGenRootView {
    @ViewBuilder var checkView: some View {
        switch root.generatorController.llm.availability {
        case .available:
            contentView
        case .unavailable(let reason):
            let text: String = switch reason {
            case .appleIntelligenceNotEnabled:
                String(
                    localized: "Apple Intelligence is not enabled. Please enable it in Settings.",
                    bundle: .module
                )
            case .deviceNotEligible:
                String(
                    localized: "This device is not eligible for Apple Intelligence. Please use a compatible device.",
                    bundle: .module
                )
            case .modelNotReady:
                String(
                    localized: "The language model is not ready yet. Please try again later.",
                    bundle: .module
                )
            @unknown default:
                String(
                    localized: "The language model is unavailable for an unknown reason.",
                    bundle: .module
                )
            }
            ContentUnavailableView {
                Label {
                    Text(verbatim: text)
                } icon: {
                    Image(systemName: "apple.intelligence.badge.xmark")
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        List(root.generatorController.model.session.transcript) { entry in
            switch entry {
                case .prompt(let prompt):
                GenericSegmentsView(segments: prompt.segments, isUser: true)
                    .listRowSeparator(.hidden)
                case .response(_):
                if let campaign = root.generatorController.model.campaign {
                    CampaignGenView(campaign: campaign)
                        .listRowSeparator(.hidden)
                }

#if compiler(>=6.4)
                case .reasoning(let reasoning):
                    GenericSegmentsView(segments: reasoning.segments, isUser: false)
                        .listRowSeparator(.hidden)
#endif
                
                case .instructions, .toolCalls, .toolOutput:
                    EmptyView()
                @unknown default:
                    Text(verbatim: String(describing: entry))
                        .textSelection(.enabled)
            }
        }
        .listStyle(.plain)
        .themedListSurface()
        .onAppear {
            root.generatorController.generateAdventure(from: model)
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
            
            Button(
                LocalizedStringResource("Send prompt", bundle: .module),
                systemImage: "apple.intelligence"
            ) {
                let message = prompt
                Task {
                    await root.generatorController.requestAdventure(message: message)
                }
                prompt = ""
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.trailing)
            .disabled(prompt.isEmpty || root.generatorController.model.session.isResponding)
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
        if let model = root.itemController.itemSync(for: GeneratorModel.previewId) {
            AdventureGenRootView(model: model, dismissAction: nil)
        }
    }
}
