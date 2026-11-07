// @copyright André Trettin

#if os(macOS)
import CoreMedia
import CoreRPG
import SwiftUI

/// The music controls of the macOS menu bar extra (`.window` style).
///
/// Same functionality as `AudioPlayerView` (which stays as it is for the other platforms and
/// windows): previous / play-pause / next, repeat, seeking, volume and the playlist. In a running
/// game the transport buttons and playlist rows go through `networkActions` like there.
struct MenuBarAudioPlayerView: View {
    @ScaledMetric(relativeTo: .body) private var width = 320

    var body: some View {
        VStack(spacing: 12) {
            MenuBarAudioTitleView()
            MenuBarAudioTransportView()
            MenuBarAudioTimeView()
            MenuBarAudioVolumeView()
            MenuBarAudioPlayListView()
        }
        .frame(width: width)
    }
}

#Preview(traits: .mockData) {
    MenuBarAudioPlayerView()
        .padding()
}

// MARK: - Subviews

private struct MenuBarAudioTitleView: View {
    @Environment(AudioRootModel.self) private var root

    var body: some View {
        Text(currentName)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
            .foregroundStyle(root.audioController.model.currentId == nil ? .secondary : .primary)
    }

    private var currentName: String {
        guard let id = root.audioController.model.currentId else {
            return String(localized: "No song currently loaded", bundle: .module)
        }
        return root.gameController.gameItem(for: id).name
    }
}

private struct MenuBarAudioTransportView: View {
    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var sideButtonSide = 32
    @ScaledMetric(relativeTo: .largeTitle) private var playButtonSide = 44

    var body: some View {
        let model = root.audioController.model
        HStack(spacing: 20) {
            Button {
                withAnimation(.default.reduced(if: reduceMotion)) {
                    root.skip(offsetBy: -1, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
                }
            } label: {
                Label {
                    Text("Previous Track", bundle: .module)
                } icon: {
                    Image(systemName: "backward.fill")
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: sideButtonSide, height: sideButtonSide)
                .contentShape(.rect)
            }
            .disabled(!model.hasPrev)

            Button {
                root.togglePlayback(isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
            } label: {
                Label {
                    if model.isPlaying {
                        Text("Pause", bundle: .module)
                    } else {
                        Text("Play", bundle: .module)
                    }
                } icon: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .contentTransition(.symbolEffect(.replace.offUp))
                }
                .labelStyle(.iconOnly)
                .font(.largeTitle)
                .frame(width: playButtonSide, height: playButtonSide)
                .contentShape(.rect)
            }
            .disabled(model.currentId == nil)

            Button {
                withAnimation(.default.reduced(if: reduceMotion)) {
                    root.skip(offsetBy: 1, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
                }
            } label: {
                Label {
                    Text("Next Track", bundle: .module)
                } icon: {
                    Image(systemName: "forward.fill")
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: sideButtonSide, height: sideButtonSide)
                .contentShape(.rect)
            }
            .disabled(!model.hasNext)

            Button {
                model.repeatPlayList.toggle()
            } label: {
                Label {
                    Text("Repeat Playlist", bundle: .module)
                } icon: {
                    Image(systemName: model.repeatPlayList ? "repeat.circle.fill" : "repeat.circle")
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(model.repeatPlayList ? Color.accentColor : .secondary)
                .frame(width: sideButtonSide, height: sideButtonSide)
                .contentShape(.rect)
            }
            .accessibilityValue(
                model.repeatPlayList
                    ? Text("Enabled", bundle: .module)
                    : Text("Disabled", bundle: .module)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.playList.isEmpty)
        .frame(maxWidth: .infinity)
    }
}

private struct MenuBarAudioTimeView: View {
    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {
        let model = root.audioController.model
        AudioPlayerScrubberView(
            currentTime: model.currentTime,
            totalDuration: model.playerTime.totalDuration,
            elapsedText: model.playerTime.elapsedText,
            onSeek: { [root, networkActions, appGameStateModel] position in
                root.seek(to: position, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
            }
        )
        .disabled(model.currentId == nil)
    }
}

private struct MenuBarAudioVolumeView: View {
    @Environment(AudioRootModel.self) private var root

    var body: some View {
        @Bindable var model = root.audioController.model
        VolumeSlider(volume: $model.volume, minIcon: "speaker.fill", maxIcon: "speaker.wave.3.fill")
            .labelsHidden()
    }
}

private struct MenuBarAudioPlayListView: View {
    @Environment(AudioRootModel.self) private var root
    @ScaledMetric(relativeTo: .body) private var maximumHeight = 180

    var body: some View {
        let model = root.audioController.model
        if !model.playList.isEmpty {
            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.playList) { audio in
                        MenuBarAudioPlayListRow(audio: audio, isCurrent: model.currentId == audio.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: maximumHeight)
        }
    }
}

private struct MenuBarAudioPlayListRow: View {
    let audio: PlaylistItem
    let isCurrent: Bool

    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Button {
                root.playOrRequest(id: audio.id, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
            } label: {
                HStack {
                    Image(systemName: "waveform")
                        .opacity(isCurrent ? 1 : 0)
                        .accessibilityHidden(true)

                    Text(verbatim: audio.title)
                        .lineLimit(1)

                    Spacer()

                    Text(verbatim: PlayerTime.formatted(time: audio.duration.seconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                withAnimation(.default.reduced(if: reduceMotion)) {
                    root.remove(id: audio.id, isGameRunning: appGameStateModel.isGameRunning, networkActions: networkActions)
                }
            } label: {
                Label {
                    Text("Delete Audio", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isCurrent ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: ResolvedAppTheme.elementCornerRadius))
    }
}
#endif
