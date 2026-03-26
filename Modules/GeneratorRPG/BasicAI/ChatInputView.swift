// @copyright André Trettin

import SwiftUI

struct ChatInputView: View {
    @Binding var messageText: String
    var chatViewModel: ChatViewModel
    @FocusState.Binding var isTextFieldFocused: Bool
    @Namespace private var glassNamespace
    
    var body: some View {
#if os(iOS) || os(macOS)
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                TextField("Type your message...", text: $messageText, axis: .vertical)
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
                .accessibilityLabel("Send message")
                .padding(12)
                .glassEffect(
                    .regular
                        .tint(.blue)
                        .interactive(true), in: .circle
                )
                .glassEffectID("sendButton", in: glassNamespace)
                .disabled(chatViewModel.isLoading || chatViewModel.isSummarizing)
#if os(macOS)
                .buttonStyle(.plain)
#endif
            }
        }
        .padding()
#else
        HStack(spacing: 12) {
            TextField("Type your message...", text: $messageText, axis: .vertical)
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
            .accessibilityLabel("Send message")
            .buttonStyle(.plain)
            .padding(8)
            .disabled(
                messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                chatViewModel.isLoading ||
                chatViewModel.isSummarizing
            )
        }
        .padding()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: messageText.isEmpty)
#endif
    }
    
    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        messageText = ""
        isTextFieldFocused = true // Keep focus for continuous conversation
        
        Task {
            await chatViewModel.sendMessage(trimmedMessage)
        }
    }
}
