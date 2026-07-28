// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation
import SwiftUI

/// A compact composer for generating transient SheetModel previews in the visible sheet.
/// The SheetRootModel owns focus, request identity, and preview lifetime; this view only
/// runs the latest immutable request and reports its result back to that model.
struct SheetAIAssistantOverlayView: View {
    let generatorController: GeneratorController
    let rootModel: SheetRootModel
    

    @State private var messageText = ""
    @State private var errorMessage: String?
    @State private var availability = SheetAIGenerationController().availability
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


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

            await Task.yield()
            guard !Task.isCancelled, rootModel.isAIModeActive else { return }
            isTextFieldFocused = true
        }
        .task(id: rootModel.pendingGenerationRequest?.id) {
            guard let request = rootModel.pendingGenerationRequest else { return }
            await generate(request)
        }
        .onChange(of: rootModel.sheetModel.source.itemId) { _, _ in
            resetForItemChange()
        }
        .task {
            MasterRPGTips.setAIAvailable(availability.isAvailable)
        }
        .onChange(of: availability) { _, newAvailability in
            MasterRPGTips.setAIAvailable(newAvailability.isAvailable)
        }
    }

    @ViewBuilder
    private var standardAssistant: some View {
        SheetAIAssistantStandardControl(
            module: rootModel.sheetModel.source.typeId,
            messageText: $messageText,
            availability: availability,
            isExpanded: rootModel.isAIModeActive,
            isGenerating: rootModel.pendingGenerationRequest != nil,
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
            //availability = generationController.availability
            rootModel.setAIModeActive(true)
        }
    }

    private func closeAIMode() {
        withAnimation(reduceMotion ? nil : .smooth) {
            isTextFieldFocused = false
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
        //availability = generationController.availability
        isTextFieldFocused = false
        rootModel.setAIModeActive(false)
    }

    private func submitPrompt() {
        let prompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        //availability = generationController.availability
        guard availability.isAvailable else { return }
        
        let request = SheetGenerationRequest(prompt: prompt, sheetContext: SheetContentSnapshot(id: UUID(), source: ItemRowModel(itemId: UUID(), typeId: .adventure), name: "", content: ""), focusedContent: nil, focus: SheetGenerationFocus(rootItemID: UUID(), parentModelID: UUID(), parentSource: ItemRowModel(itemId: UUID(), typeId: .adventure), selectedModelID: nil, selectedSource: nil, position: .end, module: .adventure))
        
//        Task {
//            try await generationController.generateDrafts(for: request)
//        }
//        let didQueue = withAnimation(reduceMotion ? nil : .smooth) {
//            guard rootModel.queueGeneration(prompt: prompt, module: module) != nil else {
//                return false
//            }
//            messageText = ""
//            errorMessage = nil
//            return true
//        }
//        guard didQueue else { return }
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
