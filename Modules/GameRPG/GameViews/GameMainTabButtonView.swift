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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                cycleDisplayMode()
            }
        } label: {
            Image(systemName: iconName)
        }
        .selectedBorderedStype(isSelected: displayMode != .hidden)
        .help(helpText)
        .accessibilityLabel(helpText)
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
    
    private var helpText: Text {
        switch displayMode {
        case .hidden:
            return Text("Show game view inline", bundle: .module)
        case .inline:
            return Text("Open game view in window", bundle: .module)
        case .window:
            return Text("Hide game view", bundle: .module)
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

#Preview("Three-State (macOS/visionOS)") {
    HStack {
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.hidden))
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.inline))
        GameMainTabButtonView(isMaster: true, displayMode: .constant(.window))
    }
    .padding()
    .background(.ultraThinMaterial)
}
