// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GeneratedValueMessageView: View {
    let summary: ItemGenerationSummary
    let dismissAction: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(.tint)

            VStack(alignment: .leading) {
                Text(summary.name)
                    .bold()
                Text(summary.value)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                String(localized: "Dismiss", bundle: .module),
                systemImage: "xmark",
                action: dismissAction
            )
                .labelStyle(.iconOnly)
#if !os(visionOS)
                .buttonStyle(.glass)
#endif
        }
        .padding()
        .frame(maxWidth: 560)
#if os(visionOS)
        .glassBackgroundEffect(in: .rect(cornerRadius: 20, style: .continuous))
#else
        .glassEffectAll(
            .regular.interactive(),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
#endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("Generated \(summary.name): \(summary.value)", bundle: .module)
        )
    }
}
