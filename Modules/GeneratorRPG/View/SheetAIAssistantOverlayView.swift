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

    public var body: some View {
        StandardAssistantView(
            generatorController: generatorController,
            rootModel: rootModel,
            messageText: $messageText,
            isTextFieldFocused: $isTextFieldFocused,
            submitAction: submitPrompt,
            toggleAction: toggleAIMode
        )
        // Bound directly to the controller's own error state (rather than a separate local
        // flag the request/extract failure paths never actually wrote to) so an on-device
        // generation failure — model unavailable, guardrail violation, decoding failure,
        // context overflow — is no longer silently swallowed. See CODE_AUDIT §5.7.
        .alert(
            Text("AI Generation Failed", bundle: .module),
            isPresented: isErrorPresented,
            actions: {
                Button(role: .cancel) {
                    generatorController.model.dismissError()
                } label: {
                    Text("OK", bundle: .module)
                }
            },
            message: {
                Text(verbatim: generatorController.model.responseErrorContent)
            }
        )
        .task(id: rootModel.isAIModeActive) {
            guard rootModel.isAIModeActive else {
                isTextFieldFocused = false
                return
            }
            if generatorController.availability {
                generatorController.seedConversationContext(sheetModel: rootModel.sheetModel)
                await generatorController.prepareEngine(module: rootModel.sheetModel.source.typeId)
            }

            await Task.yield()
            guard !Task.isCancelled, rootModel.isAIModeActive else { return }
            isTextFieldFocused = true
        }
        .onChange(of: rootModel.focusAISheetModel) { _, focused in
            guard let focused else { return }
            if !rootModel.isAIModeActive {
                activateAIMode()
            }
            submitFocusedEntry(focused)
        }
        .onChange(of: rootModel.sheetModel.source.itemId) { _, _ in
            resetForItemChange()
        }
        .task {
            MasterRPGTips.setAIAvailable(generatorController.availability)
        }
        .onDisappear {
            // Leaving this AI surface reliably stops its session — without this, `tearDown()`
            // (which cancels both the conversational and extraction tasks) had zero call
            // sites anywhere, so a generation started here kept running in the background
            // indefinitely after the user navigated away. See CODE_AUDIT §5.6.
            generatorController.tearDown()
        }
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { generatorController.model.showError },
            set: { isPresented in
                if !isPresented {
                    generatorController.model.dismissError()
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
        generatorController.model.dismissError()
        rootModel.setAIModeActive(false)
    }

    private func submitFocusedEntry(_ entry: SheetModel) {
        rootModel.focusAISheetModel = nil
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bounded here, like `GeneratorController.prompt(for:)` bounds the request later, so the
        // text counted for progress is the text that is sent.
        let content = String(entry.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_800))
        let message = content.isEmpty
            ? "Refine and expand the story around '\(name)'"
            : "Refine and expand the story around '\(name)': \(content)"
        generatorController.request(message: message, rootModel: rootModel)
        withAnimation(reduceMotion ? nil : .smooth) {
            generatorController.model.dismissError()
        }
    }

    private func submitPrompt() {
        let prompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        generatorController.request(message: prompt, rootModel: rootModel)

        withAnimation(reduceMotion ? nil : .smooth) {
            messageText = ""
            generatorController.model.dismissError()
        }
        isTextFieldFocused = true
    }
}

private struct StandardAssistantView: View {
    let generatorController: GeneratorController
    let rootModel: SheetRootModel
    @Binding var messageText: String
    @FocusState.Binding var isTextFieldFocused: Bool
    let submitAction: () -> Void
    let toggleAction: () -> Void

    var body: some View {
        SheetAIAssistantStandardControl(
            generatorController: generatorController,
            module: rootModel.sheetModel.source.typeId,
            messageText: $messageText,
            isExpanded: rootModel.isAIModeActive,
            isTextFieldFocused: $isTextFieldFocused,
            submitAction: submitAction,
            toggleAction: toggleAction
        )
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
