// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioPlayPauseButton: View, Equatable {
    let itemId: UUID
    
    @Environment(AudioRootModel.self) private var root
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    var body: some View {
        Button {
            handlePlayPause()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: imageSize))
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
        // If currently playing this item, just toggle pause
        if isCurrentlyPlaying {
            root.audioController.pause()
            return
        }
        
        // If a different item is playing, pause it first
        if root.audioPlayerModel.isPlaying && root.audioPlayerModel.currentId != itemId {
            root.audioController.pause()
        }
        
        // Check if this item is in the playlist
        let isInPlaylist = root.audioPlayerModel.playList.contains(where: { $0.id == itemId })
        
        if !isInPlaylist {
            // Load and play this audio item
            root.audioController.loadAndPlay(id: itemId)
        } else if root.audioPlayerModel.currentId == itemId {
            // Item is the current item but paused, just play it
            root.audioController.play()
        } else {
            // Item is in playlist but not current, switch to it
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
    
    private var imageSize: CGFloat {
        32
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
