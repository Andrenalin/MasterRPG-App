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
            playerControls
            
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

extension AudioPlayerView {
    var playerControls: some View {
        VStack {
#if os(macOS)
            volumeView
#else
            HStack {
#if os(iOS) || os(visionOS)
                volumeView
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
            
            playSkipControlView
            
            playTimeControlView
        }
    }
    
    var playPauseIcon: String {
        "\(root.audioController.model.isPlaying ? "pause" : "play").circle.fill"
    }
    
    @ViewBuilder
    var volumeView: some View {
#if os(tvOS)
        EmptyView()
#else
        @Bindable var item = root.audioController.model
        
        Slider(value: $item.volume, in: 0.0 ... 1.0) {
            Text("Volume", bundle: .module)
        } minimumValueLabel: {
            Image(systemName: "speaker")
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3")
        }
        .labelsHidden()
        .tint(Color.accentColor)
#endif
    }
    
    var playSkipControlView: some View {
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
                    networkActions?.game(root.gameController.requestPlay(id: currentId), .generic, nil)
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
        .borderLessTVBottonStyle()
        .padding(.bottom, 8)
    }
    
    var playTimeControlView: some View {
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
    
    var totalTime: Double {
        root.audioController.model.currentItem?.duration.seconds ?? 0
    }

    var currentName: String {
        guard let id = root.audioController.model.currentId else {
            return String(localized: "No song currently loaded", bundle: .module)
        }
        return root.gameController.gameItem(for: id).name
    }
}
