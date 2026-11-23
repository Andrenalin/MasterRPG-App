// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PlayerVolumeView: View {
    let root: AudioRootModel
    let alignment: Alignment

    @State private var showVolume: Bool = false

    /// The gap between the popover and its button.
    private nonisolated static let buttonGap: CGFloat = 8

    var body: some View {
        #if os(visionOS)
        VStack(alignment: .trailing) {
            PlayerVolumeChangeView(root: root, showVolume: showVolume)

            PlayerVolumeButtonView(root: root, showVolume: $showVolume)
        }
        #else
        PlayerVolumeButtonView(root: root, showVolume: $showVolume)
        .overlay(alignment: alignment) {
            PlayerVolumeChangeView(root: root, showVolume: showVolume)
                // The popover sits next to its button, on the side the alignment names: below
                // for a bottom alignment, above for a top one. No measuring needed.
                .alignmentGuide(alignment.vertical) { dimensions in
                    switch alignment.vertical {
                    case .bottom: dimensions[.top] - Self.buttonGap
                    case .top: dimensions[.bottom] + Self.buttonGap
                    default: dimensions[alignment.vertical]
                    }
                }
        }
        #endif
    }
}

/// The volume slider alone, for a panel of its own (the game table's seat panel on visionOS),
/// opened and closed by a `PlayerVolumeButtonView`.
struct PlayerVolumeSliderView: View {
    let root: AudioRootModel

    @ScaledMetric(relativeTo: .body) private var sliderWidth = 160

    var body: some View {
        @Bindable var model = root.audioController.model

        VolumeSlider(volume: $model.volume)
            .frame(width: sliderWidth)
            .tint(Color.accentColor)
    }
}

/// The volume slider popover.
private struct PlayerVolumeChangeView: View {
    let root: AudioRootModel
    let showVolume: Bool

    @ScaledMetric(relativeTo: .body) private var sliderWidth = 160

    var body: some View {
        @Bindable var model = root.audioController.model

        VStack {
            VolumeSlider(volume: $model.volume)
                .frame(width: sliderWidth)
                .tint(Color.accentColor)
        }
        .padding(8)
        .fixedSize()
        .rowEditColor(backgroundColor: .black)
        .opacity(showVolume ? 1 : 0)
        .allowsHitTesting(showVolume)
        .accessibilityHidden(!showVolume)
    }
}

#Preview {
    PlayerVolumeView(root: .preview, alignment: .bottomLeading)
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

struct PlayerVolumeButtonView: View {
    let root: AudioRootModel
    @Binding var showVolume: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VariableVolumeButton(volume: root.audioController.model.volume) {
            showVolume.toggle()
        }
        .tint(Color.accentColor)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityValue(Text(root.audioController.model.volume, format: .percent))
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}
