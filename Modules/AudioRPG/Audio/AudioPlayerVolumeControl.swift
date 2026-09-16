// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview {
    @Previewable @State var sliderVisible = true
    @Previewable @State var playerModel = AudioPlayerModel()
    AudioPlayerVolumeControl(audioPlayerModel: playerModel, isSliderVisible: $sliderVisible, onToggleMute: {})
        .padding()
}

struct AudioPlayerVolumeControl: View {
    @Bindable var audioPlayerModel: AudioPlayerModel
    @Binding var isSliderVisible: Bool
    let onToggleMute: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Constants {
        static let buttonSize: CGFloat = 32
        static let sliderWidth: CGFloat = 100
        static let height: CGFloat = 44
        static let volumeSpring = Animation.spring(response: 0.25, dampingFraction: 0.75)
    }

    var body: some View {
        HStack(spacing: 0) {
#if !os(tvOS)
            // Volume slider (visible when expanded)
            if isSliderVisible {
                VolumeSlider(volume: $audioPlayerModel.volume)
                    .frame(width: Constants.sliderWidth)
                    .tint(.primary)
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }
#endif

            // Volume button
            Button {
                handleVolumeButtonTap()
            } label: {
                Label {
                    Text(audioPlayerModel.isMuted ? "Unmute" : "Mute", bundle: .module)
                } icon: {
                    Image(systemName: volumeIcon)
                }
                .labelStyle(.iconOnly)
                .font(.body)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                Text("\(Int(audioPlayerModel.volume * 100)) percent", bundle: .module)
            )
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .frame(height: Constants.height)
        .background {
            AudioPlayerVolumeControlBackgroundView()
        }
        .contentShape(Rectangle())
        .volumeControlInteraction(
            isSliderVisible: $isSliderVisible,
            animation: reduceMotion ? nil : Constants.volumeSpring
        )
        .accessibilityAction(named: Text("Hide Volume Control", bundle: .module)) {
            guard isSliderVisible else { return }
            withAnimation(reduceMotion ? nil : Constants.volumeSpring) {
                isSliderVisible = false
            }
        }
    }

    private var volumeIcon: String {
        if audioPlayerModel.isMuted || audioPlayerModel.volume == 0 {
            "speaker.slash.fill"
        } else if audioPlayerModel.volume < 0.33 {
            "speaker.wave.1.fill"
        } else if audioPlayerModel.volume < 0.66 {
            "speaker.wave.2.fill"
        } else {
            "speaker.wave.3.fill"
        }
    }

    private func handleVolumeButtonTap() {
        // Same behavior on every platform: first tap shows the slider, second
        // tap (while already showing) mutes. See CODE_AUDIT_Audio §9.6.
        if isSliderVisible {
            withAnimation(reduceMotion ? nil : Constants.volumeSpring) {
                onToggleMute()
            }
        } else {
            withAnimation(reduceMotion ? nil : Constants.volumeSpring) {
                isSliderVisible = true
            }
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

// MARK: - Platform-specific interaction modifier

private struct VolumeControlInteractionModifier: ViewModifier {
    @Binding var isSliderVisible: Bool
    let animation: Animation?

    func body(content: Content) -> some View {
#if os(macOS)
        content
            .onHover { hovering in
                if !hovering && isSliderVisible {
                    withAnimation(animation) {
                        isSliderVisible = false
                    }
                }
            }
#else
        content
            .background {
                Button {
                    if isSliderVisible {
                        withAnimation(animation) {
                            isSliderVisible = false
                        }
                    }
                } label: {
                    Color.clear
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
#endif
    }
}

private extension View {
    func volumeControlInteraction(isSliderVisible: Binding<Bool>, animation: Animation?) -> some View {
        modifier(VolumeControlInteractionModifier(isSliderVisible: isSliderVisible, animation: animation))
    }
}
