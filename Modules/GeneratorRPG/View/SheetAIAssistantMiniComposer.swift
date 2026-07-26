// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI
import TipKit

struct SheetAIAssistantMiniComposer: View {
    let module: NetworkModules
    @Binding var messageText: String
    let availability: SheetAIGenerationAvailability
    let isActive: Bool
    let isGenerating: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let submitAction: () -> Void
    let activateAction: () -> Void
    let closeAction: () -> Void

    @ViewBuilder
    var body: some View {
        if isActive {
            HStack(spacing: 4) {
                Button(
                    String(localized: "Hide Ask AI", bundle: .module),
                    systemImage: NetworkModules.generator.icon,
                    action: closeAction
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .imageScale(.large)
                .frame(minWidth: 44, minHeight: 44)

                TextField(
                    availability.message ?? String(localized: "Type your request...", bundle: .module),
                    text: $messageText
                )
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit(submitAction)
#if os(iOS)
                .submitLabel(.send)
#endif
                .disabled(!availability.isAvailable || isGenerating)
                .overlay(alignment: .trailing) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(Text("Generating sheet content", bundle: .module))
                    }
                }
                .accessibilityLabel(Text("Ask AI", bundle: .module))
                .accessibilityHint(
                    isGenerating
                        ? Text("Generating", bundle: .module)
                        : Text("Press Return to generate sheet content", bundle: .module)
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(.rect)
            .defaultFocus(
                $isTextFieldFocused,
                true,
                priority: .userInitiated
            )
        } else {
            Button(
                String(localized: "Ask AI", bundle: .module),
                systemImage: NetworkModules.generator.icon,
                action: activateAction
            )
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .imageScale(.large)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 8)
                .contentShape(.rect)
                .disabled(!availability.isAvailable)
                .popoverTip(MasterRPGTips.askAI)
                .accessibilityHint(
                    availability.isAvailable
                        ? Text("Opens the AI request field", bundle: .module)
                        : Text(verbatim: availability.message ?? "")
                )
        }
    }
}

#Preview("Sheet AI Composer") {
    @Previewable @Namespace var namespace
    @Previewable @State var message = "Create a dramatic encounter"
    @Previewable @State var isExpanded: Bool = false
    @Previewable @FocusState var isFocused: Bool
    
    VStack {
        Text("StandardMiniComposer - iPhone TabAccessoryView")
        SheetAIAssistantMiniComposer(
            module: .adventure,
            messageText: $message,
            availability: SheetAIGenerationController().availability,
            isActive: true,
            isGenerating: false,
            isTextFieldFocused: $isFocused,
            submitAction: {},
            activateAction: {},
            closeAction: {}
        )
    }
}
#endif
