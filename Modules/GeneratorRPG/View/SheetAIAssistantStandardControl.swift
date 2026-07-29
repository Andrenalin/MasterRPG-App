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
    let generatorController: GeneratorController
    let module: NetworkModules
    @Binding var messageText: String
    let isExpanded: Bool
    @FocusState.Binding var isTextFieldFocused: Bool
    let submitAction: () -> Void
    let toggleAction: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: isExpanded ? 8 : 0) {
            Button {
                toggleAction()
            } label: {
                Label {
                    Text(isExpanded ? "Hide Ask AI" : "Ask AI", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.generator.icon)
                }
            }
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
                .disabled(!generatorController.availblity || generatorController.model.isLoading)
                .overlay(alignment: .trailing) {
                    if generatorController.model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(Text("Generating sheet content", bundle: .module))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .foregroundStyle(theme.foregroundColor)
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

#Preview("Sheet AI Composer") {
    @Previewable @Namespace var namespace
    @Previewable @State var message = "Create a dramatic encounter"
    @Previewable @State var isExpanded: Bool = false
    @Previewable @FocusState var isFocused: Bool
    
    VStack {
        SheetAIAssistantStandardControl(generatorController: GeneratorController(), module: .adventure, messageText: $message, isExpanded: true, isTextFieldFocused: $isFocused, submitAction: {}, toggleAction: {})
    }
}
#endif
