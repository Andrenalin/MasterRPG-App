// @copyright André Trettin

import SwiftUI

/// Shared volume slider used by the toolbar, mini/full player bars, and the
/// volume popover. Callers apply their own layout (`.frame`, `.padding`,
/// `.tint`, `.labelsHidden()`) externally. See CODE_AUDIT_Audio §8.2.
struct VolumeSlider: View {
    @Binding var volume: Double
    var minIcon: String?
    var maxIcon: String?

    var body: some View {
        #if os(tvOS)
        EmptyView()
        #else
        Group {
            if let minIcon, let maxIcon {
                Slider(value: $volume, in: 0...1) {
                    Text("Volume", bundle: .module)
                } minimumValueLabel: {
                    Image(systemName: minIcon)
                } maximumValueLabel: {
                    Image(systemName: maxIcon)
                }
            } else {
                Slider(value: $volume, in: 0...1) {
                    Text("Volume", bundle: .module)
                }
            }
        }
        .accessibilityValue(Text(volume, format: .percent))
        #endif
    }
}

#Preview {
    @Previewable @State var volume = 0.5
    VStack(spacing: 24) {
        VolumeSlider(volume: $volume)
        VolumeSlider(volume: $volume, minIcon: "speaker", maxIcon: "speaker.wave.3")
    }
    .padding()
}

/// Shared variable-speaker-icon volume button used by the toolbar and the
/// volume popover trigger. See CODE_AUDIT_Audio §8.2.
struct VariableVolumeButton: View {
    let volume: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Volume", bundle: .module)
            } icon: {
                Image(systemName: "volume.3", variableValue: volume)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: volume)
            }
            .labelStyle(.iconOnly)
        }
    }
}

#Preview {
    VariableVolumeButton(volume: 0.5, action: {})
}
