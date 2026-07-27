// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

struct ChatSheetRootView: View {
    let sheetRootController: ItemRootController
    let sheetRootModel: SheetRootModel
    let sheetModel: SheetModel
    @Bindable var model: AdventureSessionModel
    let generatorController: AdventureGeneratorController
    let activeAnswerParentSource: ItemRowModel?
    @Binding var prompt: String
    @FocusState.Binding var isTextFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let prepareForRequestAction: () -> Void
    let requestBlocksAction: (String) -> Void
    let extractAction: () -> Void
    let requestSheetDetailAction: (SheetModel) -> Void

    private var seedBlocks: [AdventureChatSeedBlock] {
        AdventureSheetContextBuilder.seedBlocks(from: sheetModel)
    }

    private var sourceBlocks: [AdventureChatBlockSnapshot] {
        AdventureSheetContextBuilder.sourceBlocks(from: sheetModel)
    }

    private var generatedCount: Int {
        sheetModel.generatedAnswerCount
    }

    private var selectedCount: Int {
        sheetModel.selectedGeneratedAnswerCount
    }

    private var canExtractLatestAnswer: Bool {
        !(model.adventureChat?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || !model.session.transcript.isEmpty
    }

    private var currentAnswer: String {
        model.adventureChat?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var isWorking: Bool {
        model.session.isResponding || model.extractSession.isResponding || model.isSummarizing || model.isApplyingWindow
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
                generatedCount: generatedCount,
                selectedCount: selectedCount
            )
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    SheetRootView(
                        root: sheetRootController,
                        rootModel: sheetRootModel)
                }
                .padding()
            }
            .background(.regularMaterial)
            .overlay {
                if showsEmptyState {
                    AdventureNoBlocksView()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AdventureChatComposerBar(
                prompt: $prompt,
                generatorController: generatorController,
                isTextFieldFocused: $isTextFieldFocused,
                canExtract: canExtractLatestAnswer,
                isExtracting: model.extractSession.isResponding,
                prepareForRequestAction: prepareForRequestAction,
                requestBlocksAction: requestBlocksAction,
                extractAction: extractAction
            )
        }
    }

    @ViewBuilder
    private func answerSection(for sheet: SheetModel) -> some View {
        let answers = directGeneratedAnswers(in: sheet)
        let selectedCount = selectedCount(in: answers)
        let isTaken = hasHiddenAnswers(in: answers)

        if !answers.isEmpty || showsWorking(for: sheet.source) || showsCurrentAnswer(for: sheet.source) {
            AdventureBlockListSectionHeader(
                title: resultSectionTitle,
                count: answers.count,
                systemImage: "sparkles",
                isWorking: showsWorking(for: sheet.source),
                selectedCount: selectedCount == 0 ? nil : selectedCount,
                isTaken: isTaken,
                canTake: selectedCount > 0,
                takeAction: { takeSelectedAnswers(in: sheet) },
                restoreAction: { restoreAnswers(in: sheet) },
                deleteAction: { deleteAnswers(in: sheet) }
            )
        }

        if directVisibleGeneratedAnswers(in: sheet).isEmpty && showsCurrentAnswer(for: sheet.source) {
            AdventureCurrentAnswerCard(text: currentAnswer)
        }
    }

    private var resultSectionTitle: String {
        String(localized: "Answers / Ideas", bundle: .module)
    }

    private var showsEmptyState: Bool {
        sourceBlocks.isEmpty && generatedCount == 0 && currentAnswer.isEmpty && !isWorking
    }

    private func showsWorking(for parentSource: ItemRowModel) -> Bool {
        isWorking && activeAnswerParentSource == parentSource
    }

    private func showsCurrentAnswer(for parentSource: ItemRowModel) -> Bool {
        activeAnswerParentSource == parentSource && !currentAnswer.isEmpty
    }

    private func directGeneratedAnswers(in sheet: SheetModel) -> [SheetModel] {
        sheet.entries.filter(\.isGeneratedAnswer)
    }

    private func directVisibleGeneratedAnswers(in sheet: SheetModel) -> [SheetModel] {
        directGeneratedAnswers(in: sheet).filter { !$0.isGeneratedHidden }
    }

    private func selectedCount(in answers: [SheetModel]) -> Int {
        answers.filter { $0.isGeneratedSelected && !$0.isGeneratedHidden }.count
    }

    private func hasHiddenAnswers(in answers: [SheetModel]) -> Bool {
        answers.contains(where: \.isGeneratedHidden)
    }

    private func takeSelectedAnswers(in sheet: SheetModel) {
        let answers = directGeneratedAnswers(in: sheet)
        let selectedIDs = Set(answers.filter { $0.isGeneratedSelected && !$0.isGeneratedHidden }.map(\.id))
        guard !selectedIDs.isEmpty else { return }

        withAnimation(reduceMotion ? nil : .default) {
            for answer in answers {
                if selectedIDs.contains(answer.id) {
                    answer.isGeneratedAccepted = true
                    answer.isGeneratedSelected = true
                    answer.isGeneratedHidden = false
                } else {
                    answer.isGeneratedHidden = true
                    answer.isGeneratedSelected = false
                }
            }
        }
    }

    private func restoreAnswers(in sheet: SheetModel) {
        withAnimation(reduceMotion ? nil : .default) {
            for answer in directGeneratedAnswers(in: sheet) {
                answer.isGeneratedHidden = false
                if !answer.isGeneratedAccepted {
                    answer.isGeneratedSelected = false
                }
            }
        }
    }

    private func deleteAnswers(in sheet: SheetModel) {
        withAnimation(reduceMotion ? nil : .default) {
            sheet.entries.removeAll { $0.isGeneratedAnswer }
        }
    }
}

private extension SheetModel {
    var generatedAnswerCount: Int {
        entries.reduce(0) { count, entry in
            count + (entry.isGeneratedAnswer ? 1 : 0) + entry.generatedAnswerCount
        }
    }

    var selectedGeneratedAnswerCount: Int {
        entries.reduce(0) { count, entry in
            count + (entry.isGeneratedSelected && !entry.isGeneratedHidden ? 1 : 0) + entry.selectedGeneratedAnswerCount
        }
    }
}

#Preview("Chat Sheet", traits: .mockData) {
    @Previewable @Environment(GeneratorRootModel.self) var root

    let sheetModel = AdventureChatPreviewData.sheetModel
    if let sheetRootController = root.rootManager?.itemRootController(for: .adventure),
       let rootManager = sheetRootController.rootManager {
        let generatorController = root.generatorController(
            for: .adventure,
            itemId: sheetModel.source.itemId
        )
        ChatSheetRootView(
            sheetRootController: sheetRootController,
            sheetRootModel: SheetRootModel(
                rootManager: rootManager,
                linkControllable: sheetRootController.linkControllable,
                sheetControllable: sheetRootController.sheetControllable,
                sheetModel: sheetModel,
                isEditor: false
            ),
            sheetModel: sheetModel,
            model: generatorController.model,
            generatorController: generatorController,
            activeAnswerParentSource: nil,
            prompt: .constant("Add a dangerous discovery."),
            isTextFieldFocused: FocusState<Bool>().projectedValue,
            prepareForRequestAction: {},
            requestBlocksAction: { _ in },
            extractAction: {},
            requestSheetDetailAction: { _ in }
        )
    }
}
