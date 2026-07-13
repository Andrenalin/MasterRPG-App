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
                Slider(value: $audioPlayerModel.volume, in: 0...1)
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
                Label(
                    audioPlayerModel.isMuted ? "Unmute" : "Mute",
                    systemImage: volumeIcon
                )
                .labelStyle(.iconOnly)
                .font(.body)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityValue(volumeAccessibilityValue)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .frame(height: Constants.height)
        .background {
            volumeControlBackground
        }
        .contentShape(Rectangle())
        .volumeControlInteraction(
            isSliderVisible: $isSliderVisible,
            animation: Constants.volumeSpring
        )
    }

    private var volumeControlBackground: some View {
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

    private var volumeAccessibilityValue: String {
        let percentage = Int(audioPlayerModel.volume * 100)
        return "\(percentage) percent"
    }

    private func handleVolumeButtonTap() {
#if os(macOS)
        // macOS: toggle mute if already showing slider, otherwise show slider
        if isSliderVisible {
            withAnimation(Constants.volumeSpring) {
                onToggleMute()
            }
        } else {
            withAnimation(Constants.volumeSpring) {
                isSliderVisible = true
            }
        }
#else
        // iOS/visionOS: first tap shows slider, second tap mutes
        if isSliderVisible {
            withAnimation(Constants.volumeSpring) {
                onToggleMute()
            }
        } else {
            withAnimation(Constants.volumeSpring) {
                isSliderVisible = true
            }
        }
#endif
    }
}

// MARK: - Platform-specific interaction modifier

private struct VolumeControlInteractionModifier: ViewModifier {
    @Binding var isSliderVisible: Bool
    let animation: Animation

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
            .onTapGesture {
                // Tapping the background (outside button/slider) dismisses
                if isSliderVisible {
                    withAnimation(animation) {
                        isSliderVisible = false
                    }
                }
            }
#endif
    }
}

private extension View {
    func volumeControlInteraction(isSliderVisible: Binding<Bool>, animation: Animation) -> some View {
        modifier(VolumeControlInteractionModifier(isSliderVisible: isSliderVisible, animation: animation))
    }
}
