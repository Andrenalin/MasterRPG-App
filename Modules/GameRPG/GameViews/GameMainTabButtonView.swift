// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Display mode for the game main tab
enum GameMainTabDisplayMode: Equatable {
    /// Game tab is hidden
    case hidden
    /// Game tab is shown inline within the game screen
    case inline
    /// Game tab is shown in a separate window
    case window
}

struct GameMainTabButtonView: View {
    let isMaster: Bool
    @Binding var displayMode: GameMainTabDisplayMode
    
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    
    var body: some View {
        Button {
            withAnimation {
                cycleDisplayMode()
            }
        } label: {
            Image(systemName: iconName)
#if os(iOS)
                .frame(height: 24)
#endif
        }
        .selectedBorderedStype(isSelected: displayMode != .hidden)
        .help(helpText)
    }
    
    private var iconName: String {
        switch displayMode {
        case .hidden:
            return NetworkModules.game.icon  // "gamecontroller"
        case .inline:
            return NetworkModules.game.icon  // "gamecontroller"
        case .window:
            return "gamecontroller.fill"  // Different icon for window mode
        }
    }
    
    private var helpText: String {
        switch displayMode {
        case .hidden:
            return "Show game view inline"
        case .inline:
            return "Open game view in window"
        case .window:
            return "Hide game view"
        }
    }
    
    private func cycleDisplayMode() {
        switch displayMode {
        case .hidden:
            displayMode = .inline
        case .inline:
            #if os(macOS) || os(visionOS)
            displayMode = .window
            #else
            displayMode = .hidden
            #endif
        case .window:
            displayMode = .hidden
        }
    }
}

#Preview {
    HStack {
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.hidden))
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.inline))
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.window))
    }
    .padding()
    .background(.ultraThinMaterial)
}
