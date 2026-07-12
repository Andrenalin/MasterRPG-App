// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation
import SwiftUI

/// A compact composer for generating transient SheetModel previews in the visible sheet.
/// The SheetRootModel owns focus, request identity, and preview lifetime; this view only
/// runs the latest immutable request and reports its result back to that model.
public struct SheetAIAssistantOverlayView: View {
    public init(module: NetworkModules, itemId: UUID, rootModel: SheetRootModel) {
        self.module = module
        self.itemId = itemId
        self.rootModel = rootModel
    }

    let module: NetworkModules
    let itemId: UUID
    let rootModel: SheetRootModel

    @State private var messageText = ""
    @State private var errorMessage: String?
    @State private var availability = SheetAIGenerationController().availability
    @FocusState private var isTextFieldFocused: Bool
    @Namespace private var glassNamespace

    private let generationController = SheetAIGenerationController()

    public var body: some View {
        Group {
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
        .animation(.smooth, value: rootModel.isAIModeActive)
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
                Text(errorMessage ?? "")
            }
        )
        .task(id: rootModel.isAIModeActive) {
            guard rootModel.isAIModeActive else {
                isTextFieldFocused = false
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
        withAnimation(.smooth) {
            availability = generationController.availability
            rootModel.setAIModeActive(true)
        }
    }

    private func closeAIMode() {
        withAnimation(.smooth) {
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
        let didQueue = withAnimation(.smooth) {
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
        withAnimation(.smooth) {
            errorMessage = nil
        }

        do {
            let drafts = try await generationController.generateDrafts(for: request)
            try Task.checkCancellation()
            guard rootModel.pendingGenerationRequest?.id == request.id else { return }

            let installed = withAnimation(.smooth) {
                rootModel.installGeneratedDrafts(drafts, for: request.id)
            }
            if !installed {
                withAnimation(.smooth) {
                    errorMessage = SheetAIGenerationError.emptyResponse.localizedDescription
                    rootModel.finishGenerationRequest(request.id)
                }
            }
        } catch is CancellationError {
            guard rootModel.pendingGenerationRequest?.id == request.id else { return }
            withAnimation(.smooth) {
                rootModel.finishGenerationRequest(request.id)
            }
        } catch {
            guard rootModel.pendingGenerationRequest?.id == request.id else { return }
            withAnimation(.smooth) {
                errorMessage = error.localizedDescription
                rootModel.finishGenerationRequest(request.id)
            }
        }
    }
}

private struct SheetAIAssistantOpenButton: View {
    let module: NetworkModules
    let glassNamespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Ask AI", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
            .padding()
        }
        #if os(visionOS)
        .buttonStyle(.borderedProminent)
        .tint(module.tint)
        #else
        .buttonStyle(.plain)
        .glassEffectAll(.regular.tint(module.tint).interactive(), in: .capsule)
        .glassEffectID("aiOverlay", in: glassNamespace)
        #endif
        .padding()
    }
}

private struct SheetAIAssistantComposer: View {
    let module: NetworkModules
    @Binding var messageText: String
    let availability: SheetAIGenerationAvailability
    let isGenerating: Bool
    let canSubmit: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let glassNamespace: Namespace.ID
    let submitAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            if let availabilityMessage = availability.message {
                Label(availabilityMessage, systemImage: "apple.intelligence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom) {
                TextField(
                    String(localized: "Type your request...", bundle: .module),
                    text: $messageText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit(submitAction)
                #if os(iOS)
                .submitLabel(.send)
                #endif
                .disabled(!availability.isAvailable)

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Generating sheet content", bundle: .module))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                Button(action: submitAction) {
                    Label {
                        Text("Generate", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.up")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .disabled(!canSubmit)

                Button(action: closeAction) {
                    Label {
                        Text("Close", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .animation(.smooth, value: isGenerating)
        .padding()
        #if os(visionOS)
        .background(.regularMaterial, in: .capsule)
        #else
        .glassEffectAll(.regular.tint(module.tint), in: .capsule)
        .glassEffectID("aiOverlay", in: glassNamespace)
        #endif
        .padding(.horizontal)
    }
}
#endif
