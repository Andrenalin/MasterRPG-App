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
                Group {
                    if case .listening(let partialText) = chatViewModel.voiceState {
                        Text(partialText.isEmpty ? "Listening..." : partialText)
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        TextField("Type your message...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                sendMessage()
                            }
#if os(iOS)
                            .submitLabel(.send)
#endif
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .glassEffectID("textField", in: glassNamespace)

                if chatViewModel.voiceState == .preparing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding(12)

                    Button("Cancel") {
                        chatViewModel.cancelVoiceMode()
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                } else if case .listening = chatViewModel.voiceState {
                    Button("End") {
                        Task {
                            await chatViewModel.stopVoiceModeAndSend()
                        }
                    }
                    .foregroundStyle(.white)
                    .font(.subheadline.weight(.medium))
                    .padding(12)
                    .glassEffect(
                        .regular
                            .tint(.red)
                            .interactive(true), in: .circle
                    )
                } else if case .speaking = chatViewModel.voiceState {
                    Button("Stop") {
                        chatViewModel.stopSpeaking()
                    }
                    .foregroundStyle(.white)
                    .font(.subheadline.weight(.medium))
                    .padding(12)
                    .glassEffect(
                        .regular
                            .tint(.orange)
                            .interactive(true), in: .circle
                    )
                } else if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task {
                            await chatViewModel.startVoiceMode()
                        }
                    } label: {
                        Image(systemName: "waveform")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Voice mode")
                    .padding(12)
                    .glassEffect(
                        .regular
                            .tint(.blue)
                            .interactive(true), in: .circle
                    )
                    .glassEffectID("voiceButton", in: glassNamespace)
                    .disabled(chatViewModel.voiceState.isActive && !chatViewModel.voiceState.isError)
                } else {
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
        }
        .padding()
#else
        HStack(spacing: 12) {
            Group {
                if case .listening(let partialText) = chatViewModel.voiceState {
                    Text(partialText.isEmpty ? "Listening..." : partialText)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    TextField("Type your message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            sendMessage()
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if chatViewModel.voiceState == .preparing {
                ProgressView()
                    .padding(.vertical, 8)

                Button("Cancel") {
                    chatViewModel.cancelVoiceMode()
                }
                .padding(8)
            } else if case .listening = chatViewModel.voiceState {
                Button("End") {
                    Task {
                        await chatViewModel.stopVoiceModeAndSend()
                    }
                }
                .padding(8)
            } else if case .speaking = chatViewModel.voiceState {
                Button("Stop") {
                    chatViewModel.stopSpeaking()
                }
                .padding(8)
            } else if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task {
                        await chatViewModel.startVoiceMode()
                    }
                } label: {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Voice mode")
                .buttonStyle(.plain)
                .padding(8)
                .disabled(chatViewModel.voiceState.isActive && !chatViewModel.voiceState.isError)
            } else {
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
