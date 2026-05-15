// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Display mode for the game main tab
enum GameMainTabDisplayMode: Int, Equatable {
    /// Game tab is hidden
    case hidden = 0
    /// Game tab is shown inline within the game screen
    case inline = 1
    /// Game tab is shown in a separate window (macOS/visionOS only)
    case window = 2
}

// MARK: - macOS/visionOS Three-State Button

/// Three-state button for macOS and visionOS (hidden/inline/window)
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
            displayMode = .window
        case .window:
            displayMode = .hidden
        }
    }
}

// MARK: - iOS/iPadOS/tvOS Simple Toggle Button

/// Simple toggle button for iOS, iPadOS, and tvOS (show/hide only)
struct GameMainTabToggleButtonView: View {
    let isMaster: Bool
    @Binding var isShown: Bool
    
    var body: some View {
        Button {
            withAnimation {
                isShown.toggle()
            }
        } label: {
            Image(systemName: NetworkModules.game.icon)
#if os(iOS)
                .frame(height: 24)
#endif
        }
        .selectedBorderedStype(isSelected: isShown)
    }
}

// MARK: - Previews

#Preview("Three-State (macOS/visionOS)") {
    HStack {
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.hidden))
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.inline))
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.window))
    }
    .padding()
    .background(.ultraThinMaterial)
}

#Preview("Toggle (iOS/tvOS)") {
    HStack {
        GameMainTabToggleButtonView(isMaster: true, isShown: .constant(false))
        GameMainTabToggleButtonView(isMaster: true, isShown: .constant(true))
    }
    .padding()
    .background(.ultraThinMaterial)
}

