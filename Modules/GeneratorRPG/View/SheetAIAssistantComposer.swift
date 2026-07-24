// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

/// A single, stable glass control for the regular Ask AI presentation.
///
/// Keeping the glass node alive while its contents expand avoids repeatedly
/// destroying and recreating two views with the same glass-effect identity.
/// That lifecycle could leave Liquid Glass continuously rendering after rapid
/// open/close/open interactions.
struct SheetAIAssistantStandardControl: View {
    let module: NetworkModules
    @Binding var messageText: String
    let availability: SheetAIGenerationAvailability
    let isExpanded: Bool
    let isGenerating: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let submitAction: () -> Void
    let toggleAction: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: isExpanded ? 8 : 0) {
            Button(
                isExpanded ? "Hide Ask AI" : "Ask AI",
                systemImage: NetworkModules.generator.icon,
                action: toggleAction
            )
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(theme.tint(for: module))
            .frame(minWidth: 44, minHeight: 44)

            if isExpanded {
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
                .disabled(!availability.isAvailable || isGenerating)
                .overlay(alignment: .trailing) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(Text("Generating sheet content", bundle: .module))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, isExpanded ? 12 : 0)
        .padding(.vertical, isExpanded ? 8 : 0)
        .animation(reduceMotion ? nil : .smooth, value: isExpanded)
#if os(visionOS)
        .background(.regularMaterial, in: .capsule)
#else
        .glassEffectAll(
            .regular.tint(theme.tint(for: module)).interactive(),
            in: .capsule
        )
#endif
        .padding([.trailing, .bottom])
    }
}

struct SheetAIAssistantComposer: View {
    let module: NetworkModules
    @Binding var messageText: String
    let availability: SheetAIGenerationAvailability
    let isGenerating: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let glassNamespace: Namespace.ID
    let submitAction: () -> Void
    let closeAction: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom) {
            Button("Hide Ask AI", systemImage: NetworkModules.generator.icon, action: closeAction)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(theme.tint(for: module))
                .accessibilityLabel(Text("Hide Ask AI", bundle: .module))

            TextField(
                String(localized: "Type your request...", bundle: .module),
                text: $messageText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .frame(maxWidth: .infinity)
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
        }
        .animation(reduceMotion ? nil : .smooth, value: isGenerating)
        .padding()
#if os(visionOS)
        .background(.regularMaterial, in: .capsule)
#else
        .glassEffectAll(
            .regular.tint(theme.tint(for: module)).interactive(),
            in: .capsule
        )
        .glassEffectID("aiOverlay", in: glassNamespace)
#endif
        .padding(.horizontal)
        .padding(.bottom)
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
        .allowsHitTesting(true)
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
        isTextFieldFocused: $isFocused,
        glassNamespace: namespace,
        submitAction: {},
        closeAction: {}
    )
}
#endif
