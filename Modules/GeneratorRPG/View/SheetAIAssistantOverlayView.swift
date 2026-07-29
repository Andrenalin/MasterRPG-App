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
                generatorController.seedConversationContext(sheetModel: rootModel.sheetModel)
                await generatorController.preparaEngine(module: rootModel.sheetModel.source.typeId)
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

    private func submitFocusedEntry(_ entry: SheetModel) {
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if content.isEmpty {
            message = String("Refine and expand the story around '\(name)'")
        } else {
            message = String("Refine and expand the story around '\(name)': \(content)")
        }
        generatorController.request(message: message, rootModel: rootModel)
        withAnimation(reduceMotion ? nil : .smooth) {
            errorMessage = nil
        }
    }

    private func submitPrompt() {
        let prompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        generatorController.request(message: prompt, rootModel: rootModel)

        withAnimation(reduceMotion ? nil : .smooth) {
            messageText = ""
            errorMessage = nil
        }
        isTextFieldFocused = true
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
