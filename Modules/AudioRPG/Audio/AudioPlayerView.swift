// @copyright André Trettin

import CoreRPG
import AVKit
import SwiftUI

struct AudioPlayerView: View {
    @Environment(AudioRootModel.self) private var root
    
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    
    static let noSong: LocalizedStringResource = "No song currently loaded"
    @State private var name: String = String(localized: noSong)
    @State private var playerTime = PlayerTime.zero
    
    @State private var currentTime = 0.0
    @State private var isEditingCurrentTime = false
    
    var body: some View {
        @Bindable var model = root.audioController.model
        VStack {
            playerControls
            
            Divider()
            
            PlayListView(root: root)
        }
        .onChange(of: model.currentId, initial: true) {
            guard let id = model.currentId else { return }
            withAnimation(.easeInOut) {
                name <=> root.gameController.gameItem(for: id).name
            }
        }
        .onChange(of: model.playerTime) {
            withAnimation(.easeInOut) {
                if !isEditingCurrentTime {
                    playerTime <=> model.playerTime
                    currentTime = model.currentTime
                }
            }
        }
    }
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
            
            Text(name)
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
                withAnimation(.easeInOut) { root.audioController.skipToCurrentItem(offsetBy: -1) }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.headline)
                    .foregroundStyle((root.audioController.model.currentIndex ?? 0) > 0 ? Color.teal : Color.secondary)
            }
            
            Button {
                if let currentId = root.audioController.model.currentId, showGame {
                    networkActions?.game(root.gameController.requestPlay(id: currentId), .generic, nil)
                } else {
                    root.audioController.toggle()
                }
            } label: {
                Image(systemName: playPauseIcon)
                    .contentTransition(.symbolEffect(.replace.offUp))
                    .font(.largeTitle)
                    .foregroundStyle(root.audioController.model.playList.isEmpty ? Color.secondary : Color.teal)
            }
            .disabled(root.audioController.model.currentId == nil)
            
            Button {
                withAnimation(.easeInOut) { root.audioController.skipToCurrentItem(offsetBy: 1) }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.headline)
                    .foregroundStyle((root.audioController.model.currentIndex ?? 0 < root.audioController.model.playList.count - 1) ? Color.teal : Color.secondary)
            }
            
            Button {
                root.audioController.model.repeatPlayList.toggle()
            } label: {
                Image(systemName: "repeat.circle\(root.audioController.model.repeatPlayList ? ".fill" : "")")
                    .font(.title)
            }
        }
        .disabled(root.audioController.model.playList.isEmpty)
        .borderLessTVBottonStyle()
        .padding(.bottom, 8)
    }
    
    var playTimeControlView: some View {
        VStack {
            HStack {
                Text(root.audioController.model.playerTime.elapsedText)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                
                Spacer()
                
                Text(root.audioController.model.playerTime.remainingText)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            .font(.system(size: 14, weight: .semibold))
            
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
#endif
        }
    }
    
    var totalTime: Double {
        root.audioController.model.currentItem?.duration.seconds ?? 0
    }
}
