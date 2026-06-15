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
    
    @State private var prompt: String = "Create a new Campaign for DungeonSlayer under the mountain in an old deserted Dwarven empire."
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
                Text("Welcome to the AI Assisent.", bundle: .module)
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
                        await root.generatorController.requestAdventure(message: message)
                    }
                    prompt = ""
                } label: {
                    Image(systemName: "gear")
                }
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
                GenericSegmentsView(segments: prompt.segments, isUser: true)
                    .listRowSeparator(.hidden)
                case .response(_):
                if let campaign = root.generatorController.model.campaign {
                    CampaignGenView(campaign: campaign)
                        .listRowSeparator(.hidden)
                }
                
                case .instructions, .toolCalls, .toolOutput:
                    EmptyView()
                @unknown default:
                    EmptyView()
            }
        }
        .listStyle(.plain)
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
            
            Button {
                let message = prompt
                Task {
                    await root.generatorController.requestAdventure(message: message)
                }
                prompt = ""
            } label: {
                Image(systemName: "apple.intelligence")
            }
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
        if let model = root.itemController.itemSync(for: MockData.previewId) {
            AdventureGenRootView(model: model, dismissAction: nil)
        }
    }
}

struct CampaignGenView: View {
    let campaign: CampaignGenModel.PartiallyGenerated
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = campaign.name {
                    Text("Campaign: \(title)", bundle: .module)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                if let description = campaign.description {
                    Text(description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                if let tags = campaign.tags {
                    TagItemRow(tags: tags)
                        .contentTransition(.opacity)
                }
            }
            
            if let adventures = campaign.entries {
                ForEach(adventures, id: \.id) { adventure in
                    AdventureGenView(adventure: adventure)
                        .padding(.leading)
                        .background(.tint.opacity(0.3))
                }
            }
        }
        .animation(.easeOut, value: campaign)
    }
}

struct AdventureGenView: View {
    let adventure: AdventureGenModel.PartiallyGenerated
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = adventure.name {
                    Text("Adventure: \(title)", bundle: .module)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                if let description = adventure.description {
                    Text(description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                if let tags = adventure.tags {
                    TagItemRow(tags: tags)
                        .contentTransition(.opacity)
                }
            }
            
            if let scenarios = adventure.entries {
                ForEach(scenarios, id: \.id) { scenario in
                    ScenarioGenView(scenario: scenario)
                        .padding(.leading)
                        .background(.tint.opacity(0.3))
                }
            }
        }
        .animation(.easeOut, value: adventure)
    }
}

struct ScenarioGenView: View {
    let scenario: ScenarioGenModel.PartiallyGenerated
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = scenario.name {
                    Text("Scenario: \(title)", bundle: .module)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                if let description = scenario.description {
                    Text(description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                if let tags = scenario.tags {
                    TagItemRow(tags: tags)
                        .contentTransition(.opacity)
                }
            }
            
            if let entries = scenario.entries {
                ForEach(entries, id: \.id) { entry in
                    EntryGenView(entry: entry)
                        .padding(.leading)
                        .background(.tint.opacity(0.3))
                }
            }
        }
        .animation(.easeOut, value: scenario)
    }
}

struct EntryGenView: View {
    let entry: EntryGenModel.PartiallyGenerated
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = entry.name {
                    Text(title)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                if let description = entry.content {
                    Text(description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.easeOut, value: entry)
    }
}

struct CharacterGenView: View {
    let value: CharacterGenModel
    let level: Int
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(value.name)
                .font(.headline)
                .textSelection(.enabled)
            Text(value.information)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            
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

struct GenericSegmentsView: View {
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
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                        .background(isUser ? Color.blue.opacity(0.2) : nil)
                        .clipShape(.rect(cornerRadius: 8))
                        .contentTransition(.interpolate)
                        .animation(.easeInOut(duration: 0.3), value: sturcture.description)
                    }
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
