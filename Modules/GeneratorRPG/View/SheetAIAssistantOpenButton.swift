// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

struct SheetAIAssistantOpenButton: View {
    let module: NetworkModules
    let glassNamespace: Namespace.ID
    let action: () -> Void

#if os(iOS)
    @Environment(\.tabViewBottomAccessoryPlacement) private var tabAccessoryPlacement
#endif

    var body: some View {
        Button(action: action) {
#if os(iOS)
            if tabAccessoryPlacement == .inline {
                Label {
                    Text("Ask AI", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.generator.icon)
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
            } else {
                regularLabel
            }
#else
            regularLabel
#endif
        }
#if os(iOS)
        .accessibilityLabel(Text("Ask AI", bundle: .module))
#endif
#if os(visionOS)
        .buttonStyle(.borderedProminent)
        .tint(module.tint)
#else
        .buttonStyle(.plain)
        .glassEffectAll(.regular.tint(module.tint).interactive(), in: .capsule)
        .glassEffectID("aiOverlay", in: glassNamespace)
#endif
#if !os(iOS)
        .padding()
#endif
    }

    private var regularLabel: some View {
        Label {
            Text("Ask AI", bundle: .module)
        } icon: {
            Image(systemName: NetworkModules.generator.icon)
        }
        .padding()
    }
}

#Preview("Sheet AI Open Button") {
    @Previewable @Namespace var namespace
    SheetAIAssistantOpenButton(module: .adventure, glassNamespace: namespace, action: {})
}
#endif
