// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

struct SheetAIAssistantOpenButton: View {
    let module: NetworkModules
    let glassNamespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Ask AI", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
            .padding()
        }
#if os(visionOS)
        .buttonStyle(.borderedProminent)
        .tint(module.tint)
#else
        .buttonStyle(.plain)
        .glassEffectAll(.regular.tint(module.tint).interactive(), in: .capsule)
        .glassEffectID("aiOverlay", in: glassNamespace)
#endif
        .padding()
    }
}

#Preview("Sheet AI Open Button") {
    @Previewable @Namespace var namespace
    SheetAIAssistantOpenButton(module: .adventure, glassNamespace: namespace, action: {})
}
#endif
