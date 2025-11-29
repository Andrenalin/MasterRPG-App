// @copyright André Trettin

import CoreRPG
import SwiftUI
import AudioRPG

struct OverlayGameMenu: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool
    
    @Environment(GameScreenModel.self) private var gameScreenModel
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(\.wideMode) private var wideMode
    
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
                root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: wideMode == .small ? .bottom : .bottomTrailing)
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
        wideMode == .small ? 4 : 8
    }
    
    @ViewBuilder
    var titleView: some View {
        if isMaster && wideMode != .small {
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
            openWindow(id: WindowIdentifier.logs.rawValue)
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
        
        GameToolBarButtonView(valueType: .game, showType: $gameScreenModel.showMainTab)
            .padding(.trailing, marginWidth)
            .onChange(of: gameScreenModel.showGameType) {
                guard gameScreenModel.showGameType != .none && gameScreenModel.showGameType != .game else { return }
#if !os(tvOS)
                openWindow(id: gameScreenModel.showGameType.linkWindowId)
#endif
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
                GameToolBarButtonView(valueType: .game, showType: $gameScreenModel.showMainTab)
            }
        }
        .padding(.trailing, marginWidth)
        .onChange(of: gameScreenModel.showGameType) {
            guard gameScreenModel.showGameType != .none && gameScreenModel.showGameType != .game else { return }
#if !os(tvOS)
            openWindow(id: gameScreenModel.showGameType.linkWindowId)
#endif
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
    .environment(\.wideMode, .wide)
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
    .environment(\.wideMode, .small)
}
