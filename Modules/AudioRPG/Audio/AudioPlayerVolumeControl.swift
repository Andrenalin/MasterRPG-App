// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview {
    @Previewable @State var sliderVisible = true
    @Previewable @State var playerModel = AudioPlayerModel()
    AudioPlayerVolumeControl(audioPlayerModel: playerModel, isSliderVisible: $sliderVisible)
        .padding()
}

/// The volume button of the player bar: it only opens and closes the volume slider. The slider
/// is not drawn here but over the timeline, where it takes the place of the title and subtitle
/// and leaves the artwork (`AudioPlayerTimelineView`); a mute is a slider dragged to zero.
struct AudioPlayerVolumeControl: View {
    let audioPlayerModel: AudioPlayerModel
    @Binding var isSliderVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Constants {
        static let buttonSize: CGFloat = 32
        static let height: CGFloat = 44
        static let volumeSpring = Animation.spring(response: 0.25, dampingFraction: 0.75)
        /// Volumes below which the speaker shows one and two waves.
        static let lowVolume = 0.33
        static let mediumVolume = 0.66
    }

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : Constants.volumeSpring) {
                isSliderVisible.toggle()
            }
        } label: {
            Label {
                Text("Volume", bundle: .module)
            } icon: {
                Image(systemName: volumeIcon)
            }
            .labelStyle(.iconOnly)
            .font(.body)
            .frame(width: Constants.buttonSize, height: Constants.buttonSize)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(audioPlayerModel.volume, format: .percent))
        .accessibilityHint(Text(isSliderVisible ? "Hide Volume Control" : "Show Volume Control", bundle: .module))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: Constants.height)
        .background {
            AudioPlayerVolumeControlBackgroundView()
        }
        .contentShape(.rect)
    }

    private var volumeIcon: String {
        if audioPlayerModel.isMuted {
            "speaker.slash.fill"
        } else if audioPlayerModel.volume < Constants.lowVolume {
            "speaker.wave.1.fill"
        } else if audioPlayerModel.volume < Constants.mediumVolume {
            "speaker.wave.2.fill"
        } else {
            "speaker.wave.3.fill"
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct AudioPlayerVolumeControlBackgroundView: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial.opacity(0.8))
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.12),
                                .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
#if !os(visionOS)
                    .glassEffect(.regular.tint(.white.opacity(0.03)).interactive())
#endif
            }
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
    }
}
