// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

enum AdventureChatInterfaceVariation: String, CaseIterable, Identifiable {
    case studio
    case board
    case outline

    var id: Self { self }

    var title: String {
        switch self {
        case .studio: "Studio"
        case .board: "Board"
        case .outline: "Outline"
        }
    }

    var systemImage: String {
        switch self {
        case .studio: "rectangle.split.2x1"
        case .board: "square.grid.2x2"
        case .outline: "sidebar.leading"
        }
    }
}

struct AdventureChatRootView: View {
    let sheetModel: SheetModel
    var dismissAction: (() -> Void)? = nil

    private let usesAvailabilityGate: Bool
    private let previewBlocks: [AdventureChatBlockSnapshot]?

    @Environment(GeneratorRootModel.self) private var root
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var scrollID: String?
    @State private var prompt: String = ""
    @State private var selectedBlocks: Set<String> = []
    @State private var focusedBlockID: String?
    @State private var didSendInitialContext = false
    @State private var selectedVariation: AdventureChatInterfaceVariation

    @FocusState private var isTextFieldFocused: Bool

    init(
        sheetModel: SheetModel,
        dismissAction: (() -> Void)? = nil,
        interfaceVariation: AdventureChatInterfaceVariation = .studio,
        usesAvailabilityGate: Bool = true,
        previewBlocks: [AdventureChatBlockSnapshot]? = nil
    ) {
        self.sheetModel = sheetModel
        self.dismissAction = dismissAction
        self.usesAvailabilityGate = usesAvailabilityGate
        self.previewBlocks = previewBlocks
        self._selectedVariation = State(initialValue: interfaceVariation)
    }

    private var model: AdventureSessionModel {
        generatorController.model
    }

    private var generatorController: AdventureGeneratorController {
        root.adventureGeneratorController
    }

    var body: some View {
        Group {
            if usesAvailabilityGate {
                FoundationBasicView {
                    contentView
                }
            } else {
                contentView
            }
        }
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
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: close)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark", action: commitSelection)
                    .disabled(selectedGeneratedBlocks.isEmpty)
            }
        }
    }
}

private extension AdventureChatRootView {
    @ViewBuilder var contentView: some View {
        @Bindable var model = model

        AdventureChatWorkspace(
            sheetModel: sheetModel,
            model: model,
            generatorController: generatorController,
            previewBlocks: previewBlocks,
            selectedVariation: $selectedVariation,
            selectedBlocks: $selectedBlocks,
            focusedBlockID: $focusedBlockID,
            scrollID: $scrollID,
            prompt: $prompt,
            isTextFieldFocused: $isTextFieldFocused,
            extractAction: extractLatestAnswer,
            requestDetailAction: requestDetail,
            commitAction: commitSelection
        )
        .alert(
            "Error",
            isPresented: $model.showError,
            actions: { Button { model.dismissError() } label: { Text("OK", bundle: .module) } },
            message: { Text(model.responseErrorContent) }
        )
        .task {
            generatorController.generateExtractor()
            await generatorController.generate()
            startConversationWithSheetContextIfNeeded()
            try? await Task.sleep(for: .seconds(0.5))
            isTextFieldFocused = true
        }
        .onDisappear {
            generatorController.tearDown()
        }
    }

    var extractedBlocks: [AdventureChatBlockSnapshot] {
        previewBlocks ?? AdventureChatBlockSnapshot.blocks(from: model.extracted)
    }

    var selectedGeneratedBlocks: [AdventureChatBlockSnapshot] {
        extractedBlocks.filter { selectedBlocks.contains($0.id) && $0.isSelectable && !$0.isEmpty }
    }

    func close() {
        if let dismissAction {
            dismissAction()
        } else {
            dismiss()
        }
    }

    func commitSelection() {
        let selectedBlocks = selectedGeneratedBlocks
        guard !selectedBlocks.isEmpty else { return }

        sheetModel.entries = selectedBlocks.enumerated().map { offset, block in
            let typeId: NetworkModules = sheetModel.source.typeId == .none ? .adventure : sheetModel.source.typeId
            let source = ItemRowModel(
                itemId: sheetModel.source.itemId,
                entryId: UUID(),
                typeId: typeId
            )
            return SheetModel(
                source: source,
                destination: sheetModel.destination,
                level: sheetModel.level + 1,
                name: block.titleForSheet(index: offset),
                description: block.content,
                entries: []
            )
        }

        if sheetModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sheetModel.name = selectedBlocks.first?.titleForSheet(index: 0) ?? "Generated Adventure"
        }

        if sheetModel.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sheetModel.description = selectedBlocks.first?.content ?? ""
        }

        sheetModel.hasChanged = true
        close()
    }

    func extractLatestAnswer() {
        guard let message = extractableMessage else { return }
        model.adventureChat = nil
        generatorController.extract(message: message)
    }

    func requestDetail(for block: AdventureChatBlockSnapshot) {
        guard !block.isEmpty else { return }
        focusedBlockID = block.id
        let title = block.titleForSheet(index: block.index)
        let blockRole = switch block.origin {
        case .sheet:
            "This block is already part of the current adventure sheet. Use it as trusted context and expand it into playable material that still fits the existing adventure."
        case .generated:
            "This block came from the current chat. Expand it into more detailed adventure material."
        }
        let message = """
        Go deeper on this adventure block and turn it into playable story material.

        \(blockRole)

        Title: \(title)
        Content: \(block.content)

        Add scenes, secrets, complications, NPC motives, player choices, and possible outcomes. Keep it structured in blocks that can be saved into an adventure sheet.
        """
        generatorController.request(message: message)
    }

    func startConversationWithSheetContextIfNeeded() {
        guard !didSendInitialContext else { return }
        didSendInitialContext = true

        guard isChatEffectivelyEmpty, let message = AdventureSheetContextBuilder.initialPrompt(for: sheetModel) else {
            return
        }
        generatorController.request(message: message)
    }

    var extractableMessage: String? {
        if let adventureChat = model.adventureChat?.trimmingCharacters(in: .whitespacesAndNewlines), !adventureChat.isEmpty {
            return adventureChat
        }

        for entry in model.session.transcript.reversed() {
            if case .response(let response) = entry,
               let text = response.segments.textContentJoined()?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
        }
        return nil
    }

    var isChatEffectivelyEmpty: Bool {
        !model.session.transcript.contains { entry in
            switch entry {
            case .instructions:
                return false
            default:
                return true
            }
        }
    }
}

struct AdventureChatWorkspace: View {
    let sheetModel: SheetModel
    @Bindable var model: AdventureSessionModel
    let generatorController: AdventureGeneratorController
    let previewBlocks: [AdventureChatBlockSnapshot]?

    @Binding var selectedVariation: AdventureChatInterfaceVariation
    @Binding var selectedBlocks: Set<String>
    @Binding var focusedBlockID: String?
    @Binding var scrollID: String?
    @Binding var prompt: String
    @FocusState.Binding var isTextFieldFocused: Bool

    let extractAction: () -> Void
    let requestDetailAction: (AdventureChatBlockSnapshot) -> Void
    let commitAction: () -> Void

    private var seedBlocks: [AdventureChatSeedBlock] {
        AdventureSheetContextBuilder.seedBlocks(from: sheetModel)
    }

    private var sourceBlocks: [AdventureChatBlockSnapshot] {
        AdventureSheetContextBuilder.sourceBlocks(from: sheetModel)
    }

    private var generatedBlocks: [AdventureChatBlockSnapshot] {
        previewBlocks ?? AdventureChatBlockSnapshot.blocks(from: model.extracted)
    }

    private var focusedBlock: AdventureChatBlockSnapshot? {
        (sourceBlocks + generatedBlocks).first { $0.id == focusedBlockID }
    }

    private var canExtractLatestAnswer: Bool {
        !(model.adventureChat?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || !model.session.transcript.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            TokenUsageBar(
                currentTokenCount: model.currentTokenCount,
                maxContextSize: model.maxContextSize,
                tokenUsageFraction: model.tokenUsageFraction
            )

            AdventureChatHeaderView(
                seedBlocks: seedBlocks,
                sourceCount: sourceBlocks.count,
                generatedCount: generatedBlocks.count,
                selectedCount: selectedBlocks.count,
                isResponding: model.session.isResponding || model.extractSession.isResponding,
                selectedVariation: $selectedVariation
            )

            Divider()

            selectedContent
        }
        .safeAreaInset(edge: .bottom) {
            AdventureChatComposerBar(
                prompt: $prompt,
                generatorController: generatorController,
                isTextFieldFocused: $isTextFieldFocused,
                canExtract: canExtractLatestAnswer,
                isExtracting: model.extractSession.isResponding,
                extractAction: extractAction
            )
        }
    }

    @ViewBuilder private var selectedContent: some View {
        switch selectedVariation {
        case .studio:
            AdventureChatStudioLayout(
                model: model,
                sourceBlocks: sourceBlocks,
                blocks: generatedBlocks,
                selectedBlocks: $selectedBlocks,
                focusedBlockID: $focusedBlockID,
                scrollID: $scrollID,
                requestDetailAction: requestDetailAction
            )
        case .board:
            AdventureChatBoardLayout(
                model: model,
                seedBlocks: seedBlocks,
                sourceBlocks: sourceBlocks,
                blocks: generatedBlocks,
                selectedBlocks: $selectedBlocks,
                focusedBlockID: $focusedBlockID,
                scrollID: $scrollID,
                requestDetailAction: requestDetailAction
            )
        case .outline:
            AdventureChatOutlineLayout(
                model: model,
                seedBlocks: seedBlocks,
                sourceBlocks: sourceBlocks,
                blocks: generatedBlocks,
                selectedBlocks: $selectedBlocks,
                focusedBlockID: $focusedBlockID,
                focusedBlock: focusedBlock,
                scrollID: $scrollID,
                requestDetailAction: requestDetailAction,
                commitAction: commitAction
            )
        }
    }
}

struct AdventureChatHeaderView: View {
    let seedBlocks: [AdventureChatSeedBlock]
    let sourceCount: Int
    let generatedCount: Int
    let selectedCount: Int
    let isResponding: Bool
    @Binding var selectedVariation: AdventureChatInterfaceVariation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Adventure Chat", systemImage: "wand.and.stars")
                    .font(.headline)

                Spacer(minLength: 0)

                if isResponding {
                    Label("Working", systemImage: "apple.intelligence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    AdventureChatMetricPill(value: seedBlocks.count, label: "Context", systemImage: "doc.text")
                    AdventureChatMetricPill(value: sourceCount, label: "Sheet Blocks", systemImage: "text.book.closed")
                    AdventureChatMetricPill(value: generatedCount, label: "Blocks", systemImage: "square.stack.3d.up")
                    AdventureChatMetricPill(value: selectedCount, label: "Selected", systemImage: "checkmark.circle")
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    AdventureSeedContextStrip(seedBlocks: seedBlocks)
                    AdventureInterfacePicker(selectedVariation: $selectedVariation)
                        .frame(maxWidth: 360)
                }

                VStack(alignment: .leading, spacing: 8) {
                    AdventureSeedContextStrip(seedBlocks: seedBlocks)
                    AdventureInterfacePicker(selectedVariation: $selectedVariation)
                }
            }
        }
        .padding()
    }
}

struct AdventureInterfacePicker: View {
    @Binding var selectedVariation: AdventureChatInterfaceVariation

    var body: some View {
        Picker("Interface", selection: $selectedVariation) {
            ForEach(AdventureChatInterfaceVariation.allCases) { variation in
                Label(variation.title, systemImage: variation.systemImage)
                    .tag(variation)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct AdventureChatMetricPill: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(value, format: .number)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }
}

struct AdventureSeedContextStrip: View {
    let seedBlocks: [AdventureChatSeedBlock]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if seedBlocks.isEmpty {
                    Label("New Adventure", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: .rect(cornerRadius: 8))
                } else {
                    ForEach(seedBlocks.prefix(6)) { block in
                        Label(block.title, systemImage: "text.book.closed")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: .rect(cornerRadius: 8))
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

struct AdventureChatComposerBar: View {
    @Binding var prompt: String
    let generatorController: AdventureGeneratorController
    @FocusState.Binding var isTextFieldFocused: Bool
    let canExtract: Bool
    let isExtracting: Bool
    let extractAction: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ChatInputView(
                messageText: $prompt,
                generatorController: generatorController,
                isTextFieldFocused: $isTextFieldFocused
            )

            Button("Extract", systemImage: "list.bullet.clipboard", action: extractAction)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!canExtract || isExtracting)
                .padding(.trailing)
                .padding(.bottom)
                .help("Extract adventure blocks")
        }
        .background(.bar)
    }
}

struct AdventureChatStudioLayout: View {
    @Bindable var model: AdventureSessionModel
    let sourceBlocks: [AdventureChatBlockSnapshot]
    let blocks: [AdventureChatBlockSnapshot]
    @Binding var selectedBlocks: Set<String>
    @Binding var focusedBlockID: String?
    @Binding var scrollID: String?
    let requestDetailAction: (AdventureChatBlockSnapshot) -> Void

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesColumns: Bool {
        horizontalSizeClass == .regular
    }
#else
    private var usesColumns: Bool { true }
#endif

    var body: some View {
        Group {
            if usesColumns {
                HStack(spacing: 0) {
                    AdventureConversationView(model: model, scrollID: $scrollID)
                        .frame(minWidth: 320)

                    Divider()

                    AdventureBlockSelectionPanel(
                        sourceBlocks: sourceBlocks,
                        blocks: blocks,
                        selectedBlocks: $selectedBlocks,
                        focusedBlockID: $focusedBlockID,
                        requestDetailAction: requestDetailAction
                    )
                    .frame(minWidth: 320)
                }
            } else {
                VStack(spacing: 0) {
                    AdventureConversationView(model: model, scrollID: $scrollID)
                        .frame(minHeight: 280)

                    Divider()

                    AdventureBlockSelectionPanel(
                        sourceBlocks: sourceBlocks,
                        blocks: blocks,
                        selectedBlocks: $selectedBlocks,
                        focusedBlockID: $focusedBlockID,
                        requestDetailAction: requestDetailAction
                    )
                }
            }
        }
    }
}

struct AdventureChatBoardLayout: View {
    @Bindable var model: AdventureSessionModel
    let seedBlocks: [AdventureChatSeedBlock]
    let sourceBlocks: [AdventureChatBlockSnapshot]
    let blocks: [AdventureChatBlockSnapshot]
    @Binding var selectedBlocks: Set<String>
    @Binding var focusedBlockID: String?
    @Binding var scrollID: String?
    let requestDetailAction: (AdventureChatBlockSnapshot) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                AdventureBoardConversationCard(model: model, scrollID: $scrollID)

                if !sourceBlocks.isEmpty {
                    AdventureSourceBoardSection(
                        blocks: sourceBlocks,
                        focusedBlockID: $focusedBlockID,
                        requestDetailAction: requestDetailAction
                    )
                }

                Label("Generated Blocks", systemImage: "square.stack.3d.up")
                    .font(.headline)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(blocks) { block in
                        AdventureBlockCard(
                            block: block,
                            isSelected: selectedBlocks.contains(block.id),
                            isFocused: focusedBlockID == block.id,
                            toggleSelectionAction: { toggleSelection(for: block) },
                            focusAction: { focusedBlockID = block.id },
                            requestDetailAction: { requestDetailAction(block) }
                        )
                    }
                }
            }
            .padding()
        }
        .overlay {
            if sourceBlocks.isEmpty && blocks.isEmpty {
                AdventureEmptyBlocksView()
            }
        }
    }

    private func toggleSelection(for block: AdventureChatBlockSnapshot) {
        if selectedBlocks.contains(block.id) {
            selectedBlocks.remove(block.id)
        } else {
            selectedBlocks.insert(block.id)
        }
    }
}

struct AdventureBoardConversationCard: View {
    @Bindable var model: AdventureSessionModel
    @Binding var scrollID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)

            AdventureConversationView(model: model, scrollID: $scrollID)
                .frame(minHeight: 240)
        }
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }
}

struct AdventureSourceBoardSection: View {
    let blocks: [AdventureChatBlockSnapshot]
    @Binding var focusedBlockID: String?
    let requestDetailAction: (AdventureChatBlockSnapshot) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Adventure Sheet Blocks", systemImage: "text.book.closed")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    AdventureBlockCard(
                        block: block,
                        isSelected: false,
                        isFocused: focusedBlockID == block.id,
                        showsSelection: false,
                        toggleSelectionAction: {},
                        focusAction: { focusedBlockID = block.id },
                        requestDetailAction: { requestDetailAction(block) }
                    )
                }
            }
        }
    }
}

struct AdventureChatOutlineLayout: View {
    @Bindable var model: AdventureSessionModel
    let seedBlocks: [AdventureChatSeedBlock]
    let sourceBlocks: [AdventureChatBlockSnapshot]
    let blocks: [AdventureChatBlockSnapshot]
    @Binding var selectedBlocks: Set<String>
    @Binding var focusedBlockID: String?
    let focusedBlock: AdventureChatBlockSnapshot?
    @Binding var scrollID: String?
    let requestDetailAction: (AdventureChatBlockSnapshot) -> Void
    let commitAction: () -> Void

    var body: some View {
        NavigationSplitView {
            List {
                if !seedBlocks.isEmpty {
                    Section("Context") {
                        ForEach(seedBlocks.prefix(12)) { block in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(block.title)
                                    .lineLimit(1)
                                Text(block.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                Section("Adventure Sheet") {
                    ForEach(sourceBlocks) { block in
                        Button {
                            focusedBlockID = block.id
                        } label: {
                            AdventureOutlineRow(
                                block: block,
                                isSelected: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Generated Blocks") {
                    ForEach(blocks) { block in
                        Button {
                            focusedBlockID = block.id
                        } label: {
                            AdventureOutlineRow(
                                block: block,
                                isSelected: selectedBlocks.contains(block.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Adventure")
        } detail: {
            if let focusedBlock {
                AdventureBlockDetailView(
                    block: focusedBlock,
                    isSelected: selectedBlocks.contains(focusedBlock.id),
                    isSelectable: focusedBlock.isSelectable,
                    toggleSelectionAction: { toggleSelection(for: focusedBlock) },
                    requestDetailAction: { requestDetailAction(focusedBlock) },
                    commitAction: commitAction
                )
            } else {
                AdventureConversationView(model: model, scrollID: $scrollID)
            }
        }
    }

    private func toggleSelection(for block: AdventureChatBlockSnapshot) {
        if selectedBlocks.contains(block.id) {
            selectedBlocks.remove(block.id)
        } else {
            selectedBlocks.insert(block.id)
        }
    }
}

struct AdventureOutlineRow: View {
    let block: AdventureChatBlockSnapshot
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconStyle)

            VStack(alignment: .leading, spacing: 4) {
                Text(block.titleForSheet(index: block.index))
                    .lineLimit(1)
                Text(block.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var iconName: String {
        if block.isSelectable {
            return isSelected ? "checkmark.circle.fill" : "circle"
        }
        return "text.book.closed"
    }

    private var iconStyle: Color {
        if block.isSelectable && isSelected {
            return .green
        }
        return .secondary
    }
}

struct AdventureBlockDetailView: View {
    let block: AdventureChatBlockSnapshot
    let isSelected: Bool
    let isSelectable: Bool
    let toggleSelectionAction: () -> Void
    let requestDetailAction: () -> Void
    let commitAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(block.titleForSheet(index: block.index))
                            .font(.title)
                            .bold()

                        Text(block.content)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 0)
                }

                HStack {
                    if isSelectable {
                        Button(isSelected ? "Remove" : "Select", systemImage: isSelected ? "checkmark.circle.fill" : "circle", action: toggleSelectionAction)
                            .buttonStyle(.bordered)
                    } else {
                        Label("Saved in Adventure", systemImage: "text.book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Go Deeper", systemImage: "text.magnifyingglass", action: requestDetailAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(block.content.isEmpty)

                    Spacer()

                    if isSelectable {
                        Button("Save", systemImage: "checkmark", action: commitAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(!isSelected)
                    }
                }
            }
            .padding()
        }
    }
}

struct AdventureBlockSelectionPanel: View {
    let sourceBlocks: [AdventureChatBlockSnapshot]
    let blocks: [AdventureChatBlockSnapshot]
    @Binding var selectedBlocks: Set<String>
    @Binding var focusedBlockID: String?
    let requestDetailAction: (AdventureChatBlockSnapshot) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !sourceBlocks.isEmpty {
                    Label("Adventure Sheet Blocks", systemImage: "text.book.closed")
                        .font(.headline)

                    ForEach(sourceBlocks) { block in
                        AdventureBlockCard(
                            block: block,
                            isSelected: false,
                            isFocused: focusedBlockID == block.id,
                            showsSelection: false,
                            toggleSelectionAction: {},
                            focusAction: { focusedBlockID = block.id },
                            requestDetailAction: { requestDetailAction(block) }
                        )
                    }
                }

                HStack {
                    Label("Generated Blocks", systemImage: "square.stack.3d.up")
                        .font(.headline)

                    Spacer()

                    Text(selectedBlocks.count, format: .number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(blocks) { block in
                    AdventureBlockCard(
                        block: block,
                        isSelected: selectedBlocks.contains(block.id),
                        isFocused: focusedBlockID == block.id,
                        toggleSelectionAction: { toggleSelection(for: block) },
                        focusAction: { focusedBlockID = block.id },
                        requestDetailAction: { requestDetailAction(block) }
                    )
                }
            }
            .padding()
        }
        .overlay {
            if sourceBlocks.isEmpty && blocks.isEmpty {
                AdventureEmptyBlocksView()
            }
        }
    }

    private func toggleSelection(for block: AdventureChatBlockSnapshot) {
        if selectedBlocks.contains(block.id) {
            selectedBlocks.remove(block.id)
        } else {
            selectedBlocks.insert(block.id)
        }
    }
}

struct AdventureBlockCard: View {
    let block: AdventureChatBlockSnapshot
    let isSelected: Bool
    let isFocused: Bool
    var showsSelection: Bool = true
    let toggleSelectionAction: () -> Void
    let focusAction: () -> Void
    let requestDetailAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.titleForSheet(index: block.index))
                        .font(.headline)
                        .lineLimit(2)

                    if block.isPending {
                        Label("Streaming", systemImage: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if showsSelection {
                    Button(isSelected ? "Selected" : "Select", systemImage: isSelected ? "checkmark.circle.fill" : "circle", action: toggleSelectionAction)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(isSelected ? "Remove from selection" : "Select for adventure")
                } else {
                    Image(systemName: "text.book.closed")
                        .foregroundStyle(.secondary)
                        .help("Saved adventure block")
                }
            }

            Text(block.content)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(isFocused ? nil : 5)
                .textSelection(.enabled)

            HStack {
                Button("Open", systemImage: "sidebar.right", action: focusAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Go Deeper", systemImage: "text.magnifyingglass", action: requestDetailAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(block.content.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderStyle, lineWidth: isSelected || isFocused ? 2 : 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    private var borderStyle: Color {
        if isSelected {
            return .green
        }
        if isFocused {
            return .orange
        }
        return .secondary.opacity(0.25)
    }
}

struct AdventureEmptyBlocksView: View {
    var body: some View {
        ContentUnavailableView(
            "No Blocks",
            systemImage: "square.stack.3d.up",
            description: Text("Extract the latest answer to choose adventure text.")
        )
    }
}

struct AdventureConversationView: View {
    @Bindable var model: AdventureSessionModel
    @Binding var scrollID: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isChatEffectivelyEmpty {
                        ContentUnavailableView(
                            "Adventure Start",
                            systemImage: "wand.and.stars",
                            description: Text("Create a new adventure or continue from the sheet context.")
                        )
                        .padding(.vertical)
                    }

                    ForEach(model.session.transcript) { entry in
                        switch entry {
                        case .prompt(let prompt):
                            ChatSegmentsView(segments: prompt.segments, isUser: true)
                                .id(entry.id)
                        case .response(let answer):
                            ChatSegmentsView(segments: answer.segments, isUser: false)
                                .id(entry.id)
                        case .instructions, .toolCalls, .toolOutput:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }

                    if model.isSummarizing {
                        AdventureProgressRow(title: "Summarizing conversation", systemImage: "text.badge.checkmark")
                            .id("summarizing")
                    }

                    if model.isApplyingWindow {
                        AdventureProgressRow(title: "Optimizing conversation history", systemImage: "arrow.triangle.2.circlepath")
                            .id("windowing")
                    }

                    Rectangle()
                        .fill(.clear)
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
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
}

struct AdventureProgressRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct ChatSegmentsView: View {
    let segments: [Transcript.Segment]
    let isUser: Bool

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            ForEach(segments, id: \.id) { segment in
                switch segment {
                case .structure(let structure):
                    ChatBubbleText(text: structure.description, isUser: isUser)
                case .text(let text):
                    ChatBubbleText(text: text.content, isUser: isUser)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .textSelection(.enabled)
    }
}

struct ChatBubbleText: View {
    let text: String
    let isUser: Bool

    var body: some View {
        Text(text)
            .padding(10)
            .background(
                isUser ? .blue.opacity(0.18) : .secondary.opacity(0.10),
                in: .rect(cornerRadius: 8)
            )
            .contentTransition(.interpolate)
            .animation(.easeInOut(duration: 0.3), value: text)
            .frame(maxWidth: 640, alignment: isUser ? .trailing : .leading)
    }
}

enum AdventureChatBlockOrigin: Hashable {
    case sheet
    case generated
}

struct AdventureChatBlockSnapshot: Identifiable, Hashable {
    let id: String
    let index: Int
    let title: String
    let content: String
    let isPending: Bool
    let origin: AdventureChatBlockOrigin

    var isEmpty: Bool {
        title.isEmpty && content.isEmpty
    }

    var isSelectable: Bool {
        origin == .generated
    }

    func titleForSheet(index: Int) -> String {
        if title.isEmpty {
            return "Adventure Block \(index + 1)"
        }
        return title
    }

    static func blocks(from entries: [BlockEntryGenModel.PartiallyGenerated]) -> [AdventureChatBlockSnapshot] {
        entries.enumerated().map { offset, entry in
            let title = cleaned(entry.title)
            let content = cleaned(entry.content)
            return AdventureChatBlockSnapshot(
                id: "\(offset)-\(entry.stableID)",
                index: offset,
                title: title,
                content: content,
                isPending: title.isEmpty || content.isEmpty,
                origin: .generated
            )
        }
    }

    private static func cleaned(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct AdventureChatSeedBlock: Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
    let depth: Int
}

enum AdventureSheetContextBuilder {
    @MainActor
    static func seedBlocks(from sheetModel: SheetModel) -> [AdventureChatSeedBlock] {
        var blocks: [AdventureChatSeedBlock] = []
        collect(from: sheetModel, path: "root", depth: 0, into: &blocks)
        return blocks
    }

    @MainActor
    static func sourceBlocks(from sheetModel: SheetModel) -> [AdventureChatBlockSnapshot] {
        var blocks: [AdventureChatSeedBlock] = []
        collectEntries(from: sheetModel.entries, path: "entry", depth: 1, into: &blocks)

        if blocks.isEmpty {
            let title = cleaned(sheetModel.name)
            let content = cleaned(sheetModel.description)
            if !title.isEmpty || !content.isEmpty {
                blocks.append(
                    AdventureChatSeedBlock(
                        id: "root",
                        title: title.isEmpty ? "Adventure" : title,
                        content: content,
                        depth: 0
                    )
                )
            }
        }

        return blocks.enumerated().map { offset, block in
            AdventureChatBlockSnapshot(
                id: "sheet-\(block.id)",
                index: offset,
                title: block.title,
                content: block.content,
                isPending: false,
                origin: .sheet
            )
        }
    }

    @MainActor
    static func initialPrompt(for sheetModel: SheetModel) -> String? {
        let blocks = seedBlocks(from: sheetModel)
        guard !blocks.isEmpty else { return nil }

        let context = blocks
            .prefix(16)
            .map { block in
                let indent = String(repeating: "  ", count: min(block.depth, 3))
                return "\(indent)- \(block.title): \(truncated(block.content, limit: 320))"
            }
            .joined(separator: "\n")

        return """
        Summarize these existing adventure sheet notes into a compact starting context for our chat. Preserve named places, NPCs, conflicts, secrets, and open story hooks. After the summary, propose the next useful adventure blocks to create.

        Existing sheet:
        \(context)
        """
    }

    @MainActor
    private static func collect(
        from sheetModel: SheetModel,
        path: String,
        depth: Int,
        into blocks: inout [AdventureChatSeedBlock]
    ) {
        let title = cleaned(sheetModel.name)
        let content = cleaned(sheetModel.description)

        if !title.isEmpty || !content.isEmpty {
            blocks.append(
                AdventureChatSeedBlock(
                    id: path,
                    title: title.isEmpty ? "Untitled" : title,
                    content: content,
                    depth: depth
                )
            )
        }

        for entry in sheetModel.entries.enumerated() {
            collect(from: entry.element, path: "\(path).entry.\(entry.offset)", depth: depth + 1, into: &blocks)
        }

        for entry in sheetModel.inlineEntries.enumerated() {
            collect(from: entry.element, path: "\(path).inline.\(entry.offset)", depth: depth + 1, into: &blocks)
        }
    }

    @MainActor
    private static func collectEntries(
        from entries: [SheetModel],
        path: String,
        depth: Int,
        into blocks: inout [AdventureChatSeedBlock]
    ) {
        for entry in entries.enumerated() {
            let sheet = entry.element
            let title = cleaned(sheet.name)
            let content = cleaned(sheet.description)
            let entryPath = "\(path).\(entry.offset)"

            if !title.isEmpty || !content.isEmpty {
                blocks.append(
                    AdventureChatSeedBlock(
                        id: entryPath,
                        title: title.isEmpty ? "Adventure Block \(blocks.count + 1)" : title,
                        content: content,
                        depth: depth
                    )
                )
            }

            collectEntries(from: sheet.entries, path: "\(entryPath).entry", depth: depth + 1, into: &blocks)
        }
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncated(_ value: String, limit: Int) -> String {
        let value = cleaned(value)
        guard value.count > limit else { return value }
        return "\(value.prefix(limit))..."
    }
}

#Preview("1 Studio - iPhone", traits: .mockData) {
    NavigationStack {
        AdventureChatPreviewHarness(variation: .studio)
            .frame(width: 430, height: 780)
    }
}

#Preview("2 Board - iPad", traits: .mockData) {
    NavigationStack {
        AdventureChatPreviewHarness(variation: .board)
            .frame(width: 900, height: 720)
    }
}

#Preview("3 Outline - macOS", traits: .mockData) {
    NavigationStack {
        AdventureChatPreviewHarness(variation: .outline)
            .frame(width: 980, height: 680)
    }
}

struct AdventureChatPreviewHarness: View {
    let variation: AdventureChatInterfaceVariation

    var body: some View {
        AdventureChatRootView(
            sheetModel: AdventureChatPreviewData.sheetModel,
            interfaceVariation: variation,
            usesAvailabilityGate: false,
            previewBlocks: AdventureChatPreviewData.blocks
        )
    }
}

enum AdventureChatPreviewData {
    @MainActor static var sheetModel: SheetModel {
        let firstEntrySource = ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
        let secondEntrySource = ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
        let thirdEntrySource = ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
        let rootSource = ItemRowModel(itemId: UUID(), typeId: .adventure)
        return SheetModel(
            source: rootSource,
            level: 0,
            name: "The Seven Rooms",
            description: "A lost fortress built by dwarves for elven envoys, with each colored hall hiding a political vow.",
            entries: [
                SheetModel(
                    source: firstEntrySource,
                    level: 1,
                    name: "Ruby Gate",
                    description: "The red chamber tests courage through a silent duel against a remembered failure.",
                    entries: []
                ),
                SheetModel(
                    source: secondEntrySource,
                    level: 1,
                    name: "Verdant Archive",
                    description: "The green room preserves the original peace treaty in living roots that answer only honest questions.",
                    entries: []
                ),
                SheetModel(
                    source: thirdEntrySource,
                    level: 1,
                    name: "Indigo Betrayal",
                    description: "The blue-violet hall replays the night an elven diplomat broke the fortress wards to save one child.",
                    entries: []
                )
            ]
        )
    }

    static var blocks: [AdventureChatBlockSnapshot] {
        [
            AdventureChatBlockSnapshot(
                id: "preview-ruby",
                index: 0,
                title: "The Ruby Gate",
                content: "The first room asks each hero to cross a bridge of red glass while whispers name the choice they regret most.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-verdant",
                index: 1,
                title: "The Verdant Archive",
                content: "Living vines bind treaty tablets to the walls. Cutting them reveals routes, but preserving them earns an elven spirit guide.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-indigo",
                index: 2,
                title: "The Indigo Betrayal",
                content: "A moonlit chamber repeats the night the fortress changed hands, allowing players to question echoes of both sides.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-forge",
                index: 3,
                title: "The White Forge",
                content: "The final hall can reforge one broken promise into a magical key, but only if the party agrees what must stay lost.",
                isPending: false,
                origin: .generated
            )
        ]
    }
}
