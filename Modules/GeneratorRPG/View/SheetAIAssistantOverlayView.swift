// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation
import SwiftUI
import FoundationModels

/// A compact composer for generating transient SheetModel previews in the visible sheet.
/// The SheetRootModel owns focus, request identity, and preview lifetime; this view only
/// runs the latest immutable request and reports its result back to that model.
struct SheetAIAssistantOverlayView: View {
    let generatorController: GeneratorController
    let rootModel: SheetRootModel
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFieldFocused: Bool

    @State private var messageText = ""
    @State private var errorMessage: String?

    public var body: some View {
        standardAssistant
        .alert(
            Text("AI Generation Failed", bundle: .module),
            isPresented: isErrorPresented,
            actions: {
                Button(role: .cancel) {
                    errorMessage = nil
                } label: {
                    Text("OK", bundle: .module)
                }
            },
            message: {
                Text(verbatim: errorMessage ?? "")
            }
        )
        .task(id: rootModel.isAIModeActive) {
            guard rootModel.isAIModeActive else {
                isTextFieldFocused = false
                return
            }
            if generatorController.availblity {
                await generatorController.preparaEngine(module: rootModel.sheetModel.source.typeId)
            }

            await Task.yield()
            guard !Task.isCancelled, rootModel.isAIModeActive else { return }
            isTextFieldFocused = true
        }
//        .task(id: rootModel.pendingGenerationRequest?.id) {
//            guard let request = rootModel.pendingGenerationRequest else { return }
//            await generate(request)
//        }
        .onChange(of: rootModel.sheetModel.source.itemId) { _, _ in
            resetForItemChange()
        }
        .task {
            MasterRPGTips.setAIAvailable(generatorController.availblity)
        }
    }

    @ViewBuilder
    private var standardAssistant: some View {
        SheetAIAssistantStandardControl(
            generatorController: generatorController,
            module: rootModel.sheetModel.source.typeId,
            messageText: $messageText,
            isExpanded: rootModel.isAIModeActive,
            isTextFieldFocused: $isTextFieldFocused,
            submitAction: submitPrompt,
            toggleAction: toggleAIMode
        )
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func activateAIMode() {
        withAnimation(reduceMotion ? nil : .smooth) {
            rootModel.setAIModeActive(true)
        }
    }

    private func closeAIMode() {
        withAnimation(reduceMotion ? nil : .smooth) {
            rootModel.setAIModeActive(false)
        }
    }

    private func toggleAIMode() {
        if rootModel.isAIModeActive {
            closeAIMode()
        } else {
            activateAIMode()
        }
    }

    private func resetForItemChange() {
        messageText = ""
        errorMessage = nil
        rootModel.setAIModeActive(false)
    }

    private func submitPrompt() {
        let prompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        generatorController.request(message: prompt, rootSheetModel: rootModel.sheetModel)

        withAnimation(reduceMotion ? nil : .smooth) {
            messageText = ""
            errorMessage = nil
        }
        isTextFieldFocused = true
    }

    @MainActor
    private func generate(_ request: SheetGenerationRequest) async {
//        guard request.focus.rootItemID == itemId else {
//            rootModel.finishGenerationRequest(request.id)
//            return
//        }
//
//        availability = generationController.availability
//        withAnimation(reduceMotion ? nil : .smooth) {
//            errorMessage = nil
//        }
//
//        do {
//            let drafts = try await generationController.generateDrafts(for: request)
//            try Task.checkCancellation()
//            guard rootModel.pendingGenerationRequest?.id == request.id else { return }
//
//            let installed = withAnimation(reduceMotion ? nil : .smooth) {
//                rootModel.installGeneratedDrafts(drafts, for: request.id)
//            }
//            if !installed {
//                withAnimation(reduceMotion ? nil : .smooth) {
//                    errorMessage = SheetAIGenerationError.emptyResponse.localizedDescription
//                    rootModel.finishGenerationRequest(request.id)
//                }
//            }
//        } catch is CancellationError {
//            guard rootModel.pendingGenerationRequest?.id == request.id else { return }
//            withAnimation(reduceMotion ? nil : .smooth) {
//                rootModel.finishGenerationRequest(request.id)
//            }
//        } catch {
//            guard rootModel.pendingGenerationRequest?.id == request.id else { return }
//            withAnimation(reduceMotion ? nil : .smooth) {
//                errorMessage = error.localizedDescription
//                rootModel.finishGenerationRequest(request.id)
//            }
//        }
    }
}

#Preview("Sheet AI Assistant") {
    @Previewable @Environment(\.appTheme) var theme
    Rectangle().fill(theme.backgroundGradient)
        .overlay {
            SheetAIAssistantOverlayView(generatorController: .init(), rootModel: .fake)
                .padding()
            
        }
}
#endif
