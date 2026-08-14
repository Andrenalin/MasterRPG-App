// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    AudioPlayPauseButton(itemId: AudioModel.previewId)
        .padding()
}

struct AudioPlayPauseButton: View, Equatable {
    let itemId: UUID

    @Environment(AudioRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions

    var body: some View {
        Button {
            handlePlayPause()
        } label: {
            Image(systemName: iconName)
                .font(.title)
                .foregroundStyle(iconColor)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44) // Minimum tap target size
        .contentShape(.rect) // Ensure entire frame is tappable
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
    
    // MARK: - Actions
    
    private func handlePlayPause() {
        if isCurrentlyPlaying {
            root.audioController.pause()
            return
        }

        // Broadcast play command to other players before changing local state
        // so requestPlay computes shouldPlay=true from the current (not-yet-playing) state.
        networkActions?.game(root.gameController.requestPlay(id: itemId), .playAudio, nil)

        if root.audioPlayerModel.isPlaying && root.audioPlayerModel.currentId != itemId {
            root.audioController.pause()
        }

        let isInPlaylist = root.audioPlayerModel.playList.contains(where: { $0.id == itemId })
        if !isInPlaylist {
            root.audioController.loadAndPlay(id: itemId)
        } else if root.audioPlayerModel.currentId == itemId {
            root.audioController.play()
        } else {
            root.audioController.togglePlay(id: itemId)
        }
    }
    
    // MARK: - Computed Properties
    
    private var isCurrentlyPlaying: Bool {
        root.audioPlayerModel.currentId == itemId && root.audioPlayerModel.isPlaying
    }
    
    private var iconName: String {
        isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill"
    }
    
    private var iconColor: Color {
        isCurrentlyPlaying ? .primary : .secondary
    }
    
    // MARK: - Accessibility
    
    private var accessibilityLabel: String {
        isCurrentlyPlaying 
            ? String(localized: "Pause", bundle: .module)
            : String(localized: "Play", bundle: .module)
    }
    
    private var accessibilityHint: String {
        isCurrentlyPlaying 
            ? String(localized: "Pauses the current audio", bundle: .module)
            : String(localized: "Plays this audio track", bundle: .module)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: AudioPlayPauseButton, rhs: AudioPlayPauseButton) -> Bool {
        lhs.itemId == rhs.itemId
    }
}
