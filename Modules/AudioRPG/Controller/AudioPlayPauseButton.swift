// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioPlayPauseButton: View, Equatable {
    let itemId: UUID
    
    @Environment(AudioRootModel.self) private var root
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    var body: some View {
        Button {
            root.audioController.togglePlay(id: itemId)
        } label: {
            Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: imageSize))
                .foregroundStyle(isCurrentlyPlaying ? .primary : .secondary)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
//        .frame(width: frameSize, height: frameSize)
    }
    
    private var isCurrentlyPlaying: Bool {
        root.audioPlayerModel.currentId == itemId && root.audioPlayerModel.isPlaying
    }
    
    private var frameSize: CGFloat {
        switch listDisplayModel.displayMode {
        case .compact:
            return 50
        case .medium:
            return 60
        case .regular:
            return 80
        }
    }
    
    private var imageSize: CGFloat {
        return 32
    }
    
    // MARK: - Equatable
    
    static func == (lhs: AudioPlayPauseButton, rhs: AudioPlayPauseButton) -> Bool {
        lhs.itemId == rhs.itemId
    }
}
