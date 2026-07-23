// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation
import SwiftUI

/// Controls whether the assistant uses its regular expandable presentation or the
/// always-ready native tab accessory presentation.
public enum SheetAIAssistantPresentation: Sendable {
    case standard
    case tabAccessory
}

/// A compact composer for generating transient SheetModel previews in the visible sheet.
/// The SheetRootModel owns focus, request identity, and preview lifetime; this view only
/// runs the latest immutable request and reports its result back to that model.
public struct SheetAIAssistantOverlayView: View {
    public init(
        module: NetworkModules,
        itemId: UUID,
        rootModel: SheetRootModel,
        presentation: SheetAIAssistantPresentation = .standard
    ) {
        self.module = module
        self.itemId = itemId
        self.rootModel = rootModel
        self.presentation = presentation
    }

    let module: NetworkModules
    let itemId: UUID
    let rootModel: SheetRootModel
    let presentation: SheetAIAssistantPresentation

    @State private var messageText = ""
    @State private var errorMessage: String?
    @State private var availability = SheetAIGenerationController().availability
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let generationController = SheetAIGenerationController()

    public var body: some View {
        Group {
            if presentation == .tabAccessory {
                SheetAIAssistantMiniComposer(
                    module: module,
                    messageText: $messageText,
                    availability: availability,
                    isGenerating: rootModel.pendingGenerationRequest != nil,
                    isTextFieldFocused: $isTextFieldFocused,
                    submitAction: submitPrompt
                )
            } else {
                standardAssistant
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: rootModel.isAIModeActive)
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
                if presentation == .standard {
                    isTextFieldFocused = false
                }
                return
            }

            availability = generationController.availability
            await Task.yield()
            guard !Task.isCancelled, rootModel.isAIModeActive else { return }
            isTextFieldFocused = true
        }
        .task(id: rootModel.pendingGenerationRequest?.id) {
            guard let request = rootModel.pendingGenerationRequest else { return }
            await generate(request)
        }
        .onChange(of: itemId) { _, _ in
            resetForItemChange()
        }
    }

    @ViewBuilder
    private var standardAssistant: some View {
#if os(visionOS)
        Group {
            if rootModel.isAIModeActive {
                SheetAIAssistantComposer(
                    module: module,
                    messageText: $messageText,
                    availability: availability,
                    isGenerating: rootModel.pendingGenerationRequest != nil,
                    canSubmit: canSubmit,
                    isTextFieldFocused: $isTextFieldFocused,
                    glassNamespace: glassNamespace,
                    submitAction: submitPrompt,
                    closeAction: closeAIMode
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                SheetAIAssistantOpenButton(
                    module: module,
                    glassNamespace: glassNamespace,
                    action: activateAIMode
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
#else
        GlassEffectContainer {
            if rootModel.isAIModeActive {
                SheetAIAssistantComposer(
                    module: module,
                    messageText: $messageText,
                    availability: availability,
                    isGenerating: rootModel.pendingGenerationRequest != nil,
                    canSubmit: canSubmit,
                    isTextFieldFocused: $isTextFieldFocused,
                    glassNamespace: glassNamespace,
                    submitAction: submitPrompt,
                    closeAction: closeAIMode
                )
            } else {
                SheetAIAssistantOpenButton(
                    module: module,
                    glassNamespace: glassNamespace,
                    action: activateAIMode
                )
            }
        }
#endif
    }

    private var canSubmit: Bool {
        availability.isAvailable &&
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            availability = generationController.availability
            rootModel.setAIModeActive(true)
        }
    }

    private func closeAIMode() {
        withAnimation(reduceMotion ? nil : .smooth) {
            isTextFieldFocused = false
            rootModel.setAIModeActive(false)
        }
    }

    private func resetForItemChange() {
        messageText = ""
        errorMessage = nil
        availability = generationController.availability
        isTextFieldFocused = false
        rootModel.setAIModeActive(false)
    }

    private func submitPrompt() {
        let prompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        availability = generationController.availability
        guard availability.isAvailable else { return }
        let didQueue = withAnimation(reduceMotion ? nil : .smooth) {
            guard rootModel.queueGeneration(prompt: prompt, module: module) != nil else {
                return false
            }
            messageText = ""
            errorMessage = nil
            return true
        }
        guard didQueue else { return }
        isTextFieldFocused = true
    }

    @MainActor
    private func generate(_ request: SheetGenerationRequest) async {
        guard request.focus.rootItemID == itemId else {
            rootModel.finishGenerationRequest(request.id)
            return
        }

        availability = generationController.availability
        withAnimation(reduceMotion ? nil : .smooth) {
            errorMessage = nil
        }

        do {
            let drafts = try await generationController.generateDrafts(for: request)
            try Task.checkCancellation()
            guard rootModel.pendingGenerationRequest?.id == request.id else { return }

            let installed = withAnimation(reduceMotion ? nil : .smooth) {
                rootModel.installGeneratedDrafts(drafts, for: request.id)
            }
            if !installed {
                withAnimation(reduceMotion ? nil : .smooth) {
                    errorMessage = SheetAIGenerationError.emptyResponse.localizedDescription
                    rootModel.finishGenerationRequest(request.id)
                }
            }
        } catch is CancellationError {
            guard rootModel.pendingGenerationRequest?.id == request.id else { return }
            withAnimation(reduceMotion ? nil : .smooth) {
                rootModel.finishGenerationRequest(request.id)
            }
        } catch {
            guard rootModel.pendingGenerationRequest?.id == request.id else { return }
            withAnimation(reduceMotion ? nil : .smooth) {
                errorMessage = error.localizedDescription
                rootModel.finishGenerationRequest(request.id)
            }
        }
    }
}

#Preview("Sheet AI Assistant") {
    SheetAIAssistantOverlayView(module: .adventure, itemId: UUID(), rootModel: .fake)
}
#endif
