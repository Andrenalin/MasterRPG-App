// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

struct SheetAIAssistantComposer: View {
    let module: NetworkModules
    @Binding var messageText: String
    let availability: SheetAIGenerationAvailability
    let isGenerating: Bool
    let canSubmit: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let glassNamespace: Namespace.ID
    let submitAction: () -> Void
    let closeAction: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading) {
            if let availabilityMessage = availability.message {
                Label {
                    Text(verbatim: availabilityMessage)
                } icon: {
                    Image(systemName: "apple.intelligence")
                }
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
                .frame(minWidth: 44, minHeight: 44)
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
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: isGenerating)
        .padding()
#if os(visionOS)
        .background(.regularMaterial, in: .capsule)
#else
        .glassEffectAll(.regular.tint(theme.tint(for: module)), in: .capsule)
        .glassEffectID("aiOverlay", in: glassNamespace)
#endif
        .padding(.horizontal)
    }
}

struct SheetAIAssistantMiniComposer: View {
    let module: NetworkModules
    @Binding var messageText: String
    let availability: SheetAIGenerationAvailability
    let isGenerating: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let submitAction: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: NetworkModules.generator.icon)
                .foregroundStyle(theme.tint(for: module))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)

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
            .accessibilityLabel(Text("Ask AI", bundle: .module))
            .accessibilityHint(
                isGenerating
                    ? Text("Generating", bundle: .module)
                    : Text("Press Return to generate sheet content", bundle: .module)
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

#Preview("Sheet AI Composer") {
    @Previewable @Namespace var namespace
    @Previewable @State var message = "Create a dramatic encounter"
    @Previewable @FocusState var isFocused: Bool
    SheetAIAssistantComposer(
        module: .adventure,
        messageText: $message,
        availability: SheetAIGenerationController().availability,
        isGenerating: false,
        canSubmit: true,
        isTextFieldFocused: $isFocused,
        glassNamespace: namespace,
        submitAction: {},
        closeAction: {}
    )
}
#endif
