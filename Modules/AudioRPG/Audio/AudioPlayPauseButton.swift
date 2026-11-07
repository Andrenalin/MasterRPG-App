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
    // Optional: the import review rows show this button outside the game environment.
    @Environment(AppGameStateModel.self) private var appGameStateModel: AppGameStateModel?

    var body: some View {
        // In a running game the row's share button (`SharingActionView`) plays and pauses,
        // so this trailing button would be a second play button.
        if appGameStateModel?.isGameRunning != true {
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
    }
    
    // MARK: - Actions
    
    private func handlePlayPause() {
        // The button only exists outside a game, so the play is always local.
        root.toggleItem(id: itemId, isGameRunning: false, networkActions: nil)
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
