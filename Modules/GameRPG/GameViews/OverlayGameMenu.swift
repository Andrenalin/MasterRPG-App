// @copyright André Trettin

import CoreRPG
import SwiftUI
import AudioRPG

struct OverlayGameMenu: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool
    
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(ScenesManager.self) private var sceneManager
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppSettingsModel.self) private var appSettingsModel
    
    var body: some View {
#if os(visionOS)
        visionProMenu
#elseif os(macOS)
        macMenu
#elseif os(tvOS)
        tvMenu
#else
        iosMenu
#endif
    }
}

private extension OverlayGameMenu {
    var visionProMenu: some View {
        HStack(alignment: .bottom, spacing: 0) {
            titleView

            HStack(alignment: .bottom, spacing: marginWidth + 4) {
                root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: .top)
                    .padding(.horizontal, marginWidth)
                    .padding(.leading, marginWidth / 2)
                    .zIndex(2)

                toolIconView
                enlargerView

                wifiView
                closeView
            }
        }
    }
    
    var macMenu: some View {
        HStack {
            titleView
            
            HStack {
                root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: .bottomTrailing)
                
                if isMaster {
                    ControlSharingView(alignment: .bottomLeading) {}
                    secondOptionView
                }
                
                toolIconView
                enlargerView
                
                wifiView
                closeView
            }
            .foregroundStyle(.secondary)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        }
    }
    
    var tvMenu: some View {
        HStack {
            Spacer()
            wifiView
            closeView
        }
        .focusSectionAll()
    }
    
    var iosMenu: some View {
        HStack(spacing: 0) {
            titleView
            
            HStack(spacing: marginWidth + 4) {
                root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: appWindowSizeModel.mode == .compact ? .bottom : .bottomTrailing)
                    .padding(.horizontal, marginWidth)
                    .padding(.leading, marginWidth / 2)
                    .zIndex(2)
                
                if isMaster {
                    ControlSharingView(alignment: .bottom) {}
                        .zIndex(1)
                }
                
                toolIconView
                enlargerView
                
                wifiView
                closeView
            }
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        }
    }
    
    var marginWidth: CGFloat {
        appWindowSizeModel.mode == .compact ? 4 : 8
    }
    
    @ViewBuilder
    var titleView: some View {
        if isMaster && appWindowSizeModel.mode == .regular {
            Text(root.gameModel.startGameTime, style: .relative)
                .font(.caption)
                .frame(maxWidth: .infinity)
        } else {
            Spacer()
        }
    }
        
    var closeView: some View {
        Button {
            gameScreenModel.showQuitGameAlert.toggle()
        } label: {
            Image(systemName: "xmark.circle")
                .imageScale(valueFor(iOS: .large, macOS: .medium, tvOS: .small, visionOS: .large))
                .frame(height: 24)
        }
        .borderLessTVBottonStyle()
        .padding(.horizontal, marginWidth)
        .padding(.trailing, marginWidth / 2)
    }
    
    var enlargerView: some View {
        Button {
            withAnimation { gameScreenModel.toggleSideBarWidth() }
        } label: {
            Image(systemName: gameScreenModel.isLargeSideBar ? "square.resize.down" : "square.resize.up")
                .imageScale(.large)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .frame(height: 24)
        }
        .selectedBorderedStype(isSelected: true)
    }
    
    var firstOptionView: some View {
        Button {
            withAnimation { gameScreenModel.resetToMainTab() }
        } label: {
            Image(systemName: NetworkModules.game.icon)
                .frame(height: 24)
        }
        .selectedBorderedStype(isSelected: gameScreenModel.showMainTab != .none)
    }
    
    var secondOptionView: some View {
        Button {
#if os(macOS) || os(visionOS)
            sceneManager.openWindow(SceneId.logs)
#else
            withAnimation { gameScreenModel.resetToSettingsTab() }
#endif
        } label: {
            Image(systemName: NetworkModules.setting.icon)
#if os(iOS)
                .frame(height: 24)
#endif
        }
        .selectedBorderedStype(isSelected: gameScreenModel.showSettingTab != .none)
    }
    
    @ViewBuilder
    var toolIconView: some View {
#if os(macOS)
        if isMaster {
            toolIconMacViewMaster
        } else {
            toolIconMacViewPlayer
        }
#else
        firstOptionView
#if os(visionOS)
        if isMaster {
            secondOptionView
        }
#else
        secondOptionView
#endif
#endif
    }
    
    @ViewBuilder
    var toolIconMacViewMaster: some View {
        @Bindable var gameScreenModel = gameScreenModel
        GameToolBarButtonView(valueType: .adventure, showType: $gameScreenModel.showGameType)
            .padding(.leading, marginWidth)
        
        GameToolBarButtonView(valueType: .audio, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .dice, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .map, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .pdf, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .photo, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .space, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .table, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .value, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .weather, showType: $gameScreenModel.showGameType)
        
        GameMainTabButtonView(isMaster: true, displayMode: $gameScreenModel.gameMainTabDisplayMode)
            .padding(.trailing, marginWidth)
            .onChange(of: gameScreenModel.showGameType) {
                guard gameScreenModel.showGameType != .none && gameScreenModel.showGameType != .game else { return }
                if sceneManager.getSceneState(for: SceneId.sceneId(for: gameScreenModel.showGameType)) == .closed {
                    sceneManager.openWindow(SceneId.sceneId(for: gameScreenModel.showGameType))
                } else {
                    sceneManager.dismissWindow(SceneId.sceneId(for: gameScreenModel.showGameType))
                }
            }
            .onChange(of: gameScreenModel.gameMainTabDisplayMode) { oldValue, newValue in
                handleMainTabDisplayModeChange(oldValue: oldValue, newValue: newValue, isMaster: true)
            }
    }
    
    @ViewBuilder
    var toolIconMacViewPlayer: some View {
        @Bindable var gameScreenModel = gameScreenModel
        if root.gameModel.gameConfig.type != .observer {
            GameToolBarButtonView(valueType: .value, showType: $gameScreenModel.showGameType)
                .padding(.leading, marginWidth)
            GameToolBarButtonView(valueType: .dice, showType: $gameScreenModel.showGameType)
        }
        
        GameToolBarButtonView(valueType: .pdf, showType: $gameScreenModel.showGameType)
            .padding(.leading, root.gameModel.gameConfig.type == .observer ? marginWidth : 0)
        
        GameToolBarButtonView(valueType: .audio, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .photo, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .space, showType: $gameScreenModel.showGameType)
        GameToolBarButtonView(valueType: .table, showType: $gameScreenModel.showGameType)
        
        Group {
            if root.gameModel.gameConfig.type != .observer {
                GameMainTabButtonView(isMaster: false, displayMode: $gameScreenModel.gameMainTabDisplayMode)
            }
        }
        .padding(.trailing, marginWidth)
        .onChange(of: gameScreenModel.showGameType) {
            guard gameScreenModel.showGameType != .none && gameScreenModel.showGameType != .game else { return }
            if sceneManager.getSceneState(for: SceneId.sceneId(for: gameScreenModel.showGameType)) == .closed {
                sceneManager.openWindow(SceneId.sceneId(for: gameScreenModel.showGameType))
            } else {
                sceneManager.dismissWindow(SceneId.sceneId(for: gameScreenModel.showGameType))
            }
        }
        .onChange(of: gameScreenModel.gameMainTabDisplayMode) { oldValue, newValue in
            handleMainTabDisplayModeChange(oldValue: oldValue, newValue: newValue, isMaster: false)
        }
    }
    
    /// Handles the three-state main tab display mode changes
    func handleMainTabDisplayModeChange(oldValue: GameMainTabDisplayMode, newValue: GameMainTabDisplayMode, isMaster: Bool) {
        switch newValue {
        case .hidden:
            // Hide the game view
            gameScreenModel.showMainTab = .none
            
            // Close the appropriate window if it was open
            if isMaster {
                // Master: Close adventure viewer window
                if sceneManager.getSceneState(for: SceneId.adventureViewer) == .opened {
                    sceneManager.dismissWindow(SceneId.adventureViewer)
                }
            } else {
                // Player: Close character viewer window
                if sceneManager.getSceneState(for: SceneId.valueViewer) == .opened {
                    sceneManager.dismissWindow(SceneId.valueViewer)
                }
            }
            
            // Save preference
            if isMaster {
                appSettingsModel.autoShowMasterMainTab = false
            } else {
                appSettingsModel.autoShowPlayerMainTab = false
            }
            
        case .inline:
            // Show game view inline
            gameScreenModel.showMainTab = isMaster ? .game : .value
            
            // Close the window if it was open
            if isMaster {
                if sceneManager.getSceneState(for: SceneId.adventureViewer) == .opened {
                    sceneManager.dismissWindow(SceneId.adventureViewer)
                }
            } else {
                if sceneManager.getSceneState(for: SceneId.valueViewer) == .opened {
                    sceneManager.dismissWindow(SceneId.valueViewer)
                }
            }
            
            // Save preference
            if isMaster {
                appSettingsModel.autoShowMasterMainTab = true
            } else {
                appSettingsModel.autoShowPlayerMainTab = true
            }
            
        case .window:
            // Hide inline view
            gameScreenModel.showMainTab = .none
            
            // Open as separate window with appropriate content
            #if os(macOS) || os(visionOS)
            if isMaster {
                // Master: Open adventure viewer with current adventure
                if sceneManager.getSceneState(for: SceneId.adventureViewer) == .closed, let adventureId = root.gameModel.selectedAdventure {
                    sceneManager.openWindow(SceneId.viewerId(for: .adventure), selection: WindowItemSelection(itemId: adventureId))
                }
            } else {
                // Player: Open character viewer with current character
                if sceneManager.getSceneState(for: SceneId.valueViewer) == .closed, let characterId = root.gameModel.selectedCharacter {
                    sceneManager.openWindow(SceneId.viewerId(for: .value), selection: WindowItemSelection(itemId: characterId))
                }
            }
            #endif
            
            // Save preference (consider window mode as "shown")
            if isMaster {
                appSettingsModel.autoShowMasterMainTab = true
            } else {
                appSettingsModel.autoShowPlayerMainTab = true
            }
        }
    }
    
    @ViewBuilder
    var wifiView: some View {
        if !isMaster {
            Image(systemName: (playerController?.gameModel.lostMaster ?? false) ? "wifi.slash" : "wifi")
                .imageScale(.small)
                .foregroundStyle(.teal)
                .padding(.leading, marginWidth)
        }
    }
}

#Preview("wide") {
    VStack {
        OverlayGameMenu(root: .preview, playerController: .preview, isMaster: true)
            .environment(GameScreenModel())
            .padding()
    }
    .background(Color.brown)
}

#Preview("small") {
    VStack {
        OverlayGameMenu(root: .preview, playerController: .preview, isMaster: false)
            .environment(GameScreenModel())
            .frame(maxWidth: .infinity)
            .padding([.vertical])
            .padding(.trailing, 8)
    }
    .background(Color.brown)
}
