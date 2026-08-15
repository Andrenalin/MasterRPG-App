// @copyright André Trettin

import FoundationModels
import SwiftUI

struct ChatInputView: View {
    @Binding var messageText: String
    let generatorController: AdventureGeneratorController
    
    // Not `private`: unlike a `@FocusState` the view owns, this is a `.Binding` projection
    // supplied by the parent (functions like a `@Binding` parameter) — see CODE_AUDIT §8.5,
    // and `SheetEntryView.focusedEntryId` for the established codebase pattern.
    @FocusState.Binding var isTextFieldFocused: Bool
    var prepareForRequestAction: () -> Void = {}
    var sendMessageAction: ((String) -> Void)?
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
#if os(iOS) || os(macOS)
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                TextField(
                    LocalizedStringResource("Type your message...", bundle: .module),
                    text: $messageText,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        sendMessage()
                    }
#if os(iOS)
                    .submitLabel(.send)
#endif
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .glassEffectID("textField", in: glassNamespace)
                
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(Text("Send message", bundle: .module))
                .frame(minWidth: 44, minHeight: 44)
                .glassEffect(
                    .regular
                        .tint(.blue)
                        .interactive(true), in: .circle
                )
                .glassEffectID("sendButton", in: glassNamespace)
                .disabled(generatorController.model.isLoading || generatorController.model.isSummarizing || generatorController.model.extractSession.isResponding)
#if os(macOS)
                .buttonStyle(.plain)
#endif
            }
        }
        .padding()
#else
        HStack(spacing: 12) {
            TextField(
                LocalizedStringResource("Type your message...", bundle: .module),
                text: $messageText,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit {
                    sendMessage()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            
            
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : Color.accentColor
                    )
            }
            .accessibilityLabel(Text("Send message", bundle: .module))
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(
                messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                generatorController.model.isLoading ||
                generatorController.model.isSummarizing ||
                generatorController.model.extractSession.isResponding
            )
        }
        .padding()
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
            value: messageText.isEmpty
        )
#endif
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        messageText = ""
        isTextFieldFocused = true // Keep focus for continuous conversation
        
        prepareForRequestAction()
        if let sendMessageAction {
            sendMessageAction(trimmedMessage)
        } else {
            generatorController.request(message: trimmedMessage)
        }
    }
}

#Preview {
    @Previewable @State var messageText = "Describe a forgotten shrine"
    @Previewable @FocusState var isTextFieldFocused: Bool
    ChatInputView(
        messageText: $messageText,
        generatorController: AdventureGeneratorController(),
        isTextFieldFocused: $isTextFieldFocused,
        sendMessageAction: { _ in }
    )
}
