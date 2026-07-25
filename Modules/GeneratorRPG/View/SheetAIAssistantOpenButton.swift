// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

struct SheetAIAssistantOpenButton: View {
    let module: NetworkModules
    let glassNamespace: Namespace.ID
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Label(
                String(localized: "Ask AI", bundle: .module),
                systemImage: NetworkModules.generator.icon
            )
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
#if os(iOS)
        .accessibilityLabel(Text("Ask AI", bundle: .module))
#endif
#if os(visionOS)
        .buttonStyle(.borderedProminent)
        .moduleTint(module)
#else
        .buttonStyle(.plain)
        .glassEffectAll(
            .regular.tint(theme.tint(for: module)).interactive(),
            in: .capsule
        )
        .glassEffectID("aiOverlay", in: glassNamespace)
#endif
        .padding([.trailing, .bottom])
    }
}

#Preview("Sheet AI Open Button") {
    @Previewable @Namespace var namespace
    SheetAIAssistantOpenButton(module: .adventure, glassNamespace: namespace, action: {})
}
#endif
