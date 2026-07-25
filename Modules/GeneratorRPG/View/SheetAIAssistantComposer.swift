// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI
import TipKit

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
            .foregroundStyle(.primary)
            .imageScale(.large)
            .frame(minWidth: 44, minHeight: 44)
            .popoverTip(MasterRPGTips.askAI)

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
            Button(
                String(localized: "Hide Ask AI", bundle: .module),
                systemImage: NetworkModules.generator.icon,
                action: closeAction
            )
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
