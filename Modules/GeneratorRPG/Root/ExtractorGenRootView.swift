// @copyright André Trettin

import AndrenalinKit
import RPGValues
import FoundationModels
import SwiftUI

struct ExtractorGenRootView: View {
    let model: GeneratorModel
    var dismissAction: (() -> Void)? = nil
    
    @Environment(GeneratorRootModel.self) private var root
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var prompt: String =
            """
            After meeting several obstacles in the
            marsh the PCs find the ruins of a tower atop
            a rocky hill. Only the foun-
            dations remain of
            the ruined tower. Inside the remains of the
            tower, footprints can clearly be seen (MIN
            + RE + 6) in the vicinity of several recently
            used fire pits and some food left-
            overs.
            A secret trapdoor, camouflaged by moss
            and netting, opens to a stairway (MIN + RE
            + 2) leading downwards.
            1. GUARDROOM Two drunken brigands snore
            heavily slumped over a table. There are 4
            wine bottles on the table only one is full,
            worth 1GP).
            2. EMPTY ROOM There is an apple on the floor.
            3. STOREROOM In this room there are 4 lengths
            of 10M rope, 2 lanterns, 8 bottles of lamp
            oil, a bucket, 12 applications of weapon
            paste in a wooden casket, 14 short swords,
            9 long swords and 12 daggers.
            4. BARRELS There are 4 barrels of beer here
            each worth 5GP and 2 barrels of wine, each
            worth 10 GP. On one of the barrels there is
            a crowbar worth 1GP.
            5. DOGS CHAMBER This chamber is locked from
            the outside. Inside the brigands keep 4
            bloodhounds (use Wolf stats). The animals
            begin to bark half a minute after the party
            enters the room.
            6. CARD GAME At a tarnished and shaky wooden
            table brigands play cards (1 for each party
            member). Each brigand is carrying d20 CP.
            In addition one has 2 six-sided dice.
            7. EMPTY ROOM Not used by the brigands.
    """
    
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
                        await root.generatorController.requestExtraction(message: message)
                    }
                    prompt = ""
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
    }
}

private extension ExtractorGenRootView {
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
                case .response(let _):
                if let campaign = root.generatorController.model.extracted {
                    BlockGenView(campaign: campaign)
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
            root.generatorController.generateExtractor(from: model)
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


struct BlockGenView: View {
    let campaign: BlockGenModel.PartiallyGenerated
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = campaign.name {
                    Text(title)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                if let description = campaign.information {
                    Text(description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                if let category = campaign.blockCategory {
                    Text(category.rawValue)
                        .contentTransition(.opacity)
                }

                if let tags = campaign.tags {
                    TagItemRow(tags: tags)
                        .contentTransition(.opacity)
                }
            }
            
            if let adventures = campaign.entries {
                ForEach(adventures, id: \.id) { adventure in
                    BlockEntryGenView(entry: adventure)
                        .padding(.leading)
                        .background(.tint.opacity(0.3))
                }
            }
        }
        .animation(.easeOut, value: campaign)
    }
}


struct BlockEntryGenView: View {
    let entry: BlockEntryGenModel.PartiallyGenerated
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = entry.title {
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
