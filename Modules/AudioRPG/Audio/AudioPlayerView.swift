// @copyright André Trettin

import CoreRPG
import AVKit
import SwiftUI

struct AudioPlayerView: View {
    @Environment(AudioRootModel.self) private var root
    
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var currentTime = 0.0
    @State private var isEditingCurrentTime = false
    
    var body: some View {
        @Bindable var model = root.audioController.model
        VStack {
            AudioPlayerViewControlsView(currentTime: $currentTime, isEditingCurrentTime: $isEditingCurrentTime)

            Divider()

            PlayListView(root: root)
        }
        .onChange(of: model.playerTime) {
            withAnimation(reduceMotion ? nil : .easeInOut) {
                if !isEditingCurrentTime {
                    currentTime = model.currentTime
                }
            }
        }
    }
}

#Preview(traits: .mockData) {
    AudioPlayerView()
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `AudioPlayerView` itself that all re-evaluated whenever any
// part of `AudioPlayerView`'s body did.

private struct AudioPlayerViewControlsView: View {
    @Binding var currentTime: Double
    @Binding var isEditingCurrentTime: Bool

    @Environment(AudioRootModel.self) private var root

    var body: some View {
        VStack {
#if os(macOS)
            AudioPlayerViewVolumeView()
#else
            HStack {
#if os(iOS) || os(visionOS)
                AudioPlayerViewVolumeView()
#else
                Spacer()
#endif

                RoutePickerView()
                    .frame(maxWidth: 64)
            }
            .tint(Color.accentColor)
#endif

            Text(currentName)
                .font(.title2)
                .lineLimit(1)

            AudioPlayerViewPlaySkipControlView()

            AudioPlayerViewPlayTimeControlView(currentTime: $currentTime, isEditingCurrentTime: $isEditingCurrentTime)
        }
    }

    private var currentName: String {
        guard let id = root.audioController.model.currentId else {
            return String(localized: "No song currently loaded", bundle: .module)
        }
        return root.gameController.gameItem(for: id).name
    }
}

private struct AudioPlayerViewVolumeView: View {
    @Environment(AudioRootModel.self) private var root

    @ViewBuilder
    var body: some View {
#if os(tvOS)
        EmptyView()
#else
        @Bindable var item = root.audioController.model

        VolumeSlider(volume: $item.volume, minIcon: "speaker", maxIcon: "speaker.wave.3")
            .labelsHidden()
            .tint(Color.accentColor)
#endif
    }
}

private struct AudioPlayerViewPlaySkipControlView: View {
    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 32) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    root.audioController.skipToCurrentItem(offsetBy: -1)
                }
            } label: {
                Label {
                    Text("Previous Track", bundle: .module)
                } icon: {
                    Image(systemName: "backward.fill")
                }
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle((root.audioController.model.currentIndex ?? 0) > 0 ? Color.teal : Color.secondary)
            }
            .frame(minWidth: 44, minHeight: 44)

            Button {
                if let currentId = root.audioController.model.currentId, appGameStateModel.isGameRunning {
                    networkActions?.game(root.gameController.requestPlay(id: currentId), .playAudio, nil)
                } else {
                    root.audioController.toggle()
                }
            } label: {
                Label {
                    if root.audioController.model.isPlaying {
                        Text("Pause", bundle: .module)
                    } else {
                        Text("Play", bundle: .module)
                    }
                } icon: {
                    Image(systemName: playPauseIcon)
                        .contentTransition(.symbolEffect(.replace.offUp))
                }
                .labelStyle(.iconOnly)
                .font(.largeTitle)
                .foregroundStyle(root.audioController.model.playList.isEmpty ? Color.secondary : Color.teal)
            }
            .disabled(root.audioController.model.currentId == nil)
            .frame(minWidth: 44, minHeight: 44)

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    root.audioController.skipToCurrentItem(offsetBy: 1)
                }
            } label: {
                Label {
                    Text("Next Track", bundle: .module)
                } icon: {
                    Image(systemName: "forward.fill")
                }
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle((root.audioController.model.currentIndex ?? 0 < root.audioController.model.playList.count - 1) ? Color.teal : Color.secondary)
            }
            .frame(minWidth: 44, minHeight: 44)

            Button {
                root.audioController.model.repeatPlayList.toggle()
            } label: {
                Label {
                    Text("Repeat Playlist", bundle: .module)
                } icon: {
                    Image(systemName: "repeat.circle\(root.audioController.model.repeatPlayList ? ".fill" : "")")
                }
                .labelStyle(.iconOnly)
                .font(.title)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityValue(
                root.audioController.model.repeatPlayList
                    ? Text("Enabled", bundle: .module)
                    : Text("Disabled", bundle: .module)
            )
        }
        .disabled(root.audioController.model.playList.isEmpty)
        .borderLessTVButtonStyle()
        .padding(.bottom, 8)
    }

    private var playPauseIcon: String {
        "\(root.audioController.model.isPlaying ? "pause" : "play").circle.fill"
    }
}

private struct AudioPlayerViewPlayTimeControlView: View {
    @Binding var currentTime: Double
    @Binding var isEditingCurrentTime: Bool

    @Environment(AudioRootModel.self) private var root

    var body: some View {
        VStack {
            HStack {
                Text(verbatim: root.audioController.model.playerTime.elapsedText)
                    .font(.caption)
                    .bold()
                    .monospaced()

                Spacer()

                Text(verbatim: root.audioController.model.playerTime.remainingText)
                    .font(.caption)
                    .bold()
                    .monospaced()
            }

#if os(tvOS)
            ProgressView(value: currentTime, total: totalTime)
#else
            Slider(value: $currentTime, in: 0...totalTime) {
                Text("Time", bundle: .module)
            } onEditingChanged: { edit in
                isEditingCurrentTime = edit
                if !isEditingCurrentTime {
                    root.audioController.skip(to: TimeInterval(currentTime))
                }
            }
            .labelsHidden()
            .tint(Color.accentColor)
            .accessibilityValue(
                Text(
                    "\(Int(currentTime.rounded())) seconds of \(Int(totalTime.rounded())) seconds",
                    bundle: .module
                )
            )
#endif
        }
    }

    private var totalTime: Double {
        root.audioController.model.currentItem?.duration.seconds ?? 0
    }
}
