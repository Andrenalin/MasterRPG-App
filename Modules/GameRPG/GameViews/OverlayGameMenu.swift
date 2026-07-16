// @copyright André Trettin

import CoreRPG
import AudioRPG
import Foundation
import SwiftUI

struct OverlayGameMenu: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool
    
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppSettingsModel.self) private var appSettingsModel
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
#if os(visionOS)
        visionProMenu
#elseif os(macOS)
        macMenu
#elseif os(tvOS)
        tvMenu
#else
        IOSGameOverlayMenu(
            root: root,
            playerController: playerController,
            isMaster: isMaster
        )
#endif
    }
}

private extension OverlayGameMenu {
    var visionProMenu: some View {
        HStack(alignment: .bottom, spacing: marginWidth) {
            titleView

            HStack(alignment: .bottom, spacing: marginWidth + 4) {
                root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: .top)
                    .padding(.horizontal, marginWidth)
                    .padding(.leading, marginWidth / 2)
                    .zIndex(2)
                
                toolIconView
                enlargerView
                
                // TableTop Kit Table Volume Button
                gameTableButton

                wifiView
            }

            closeFieldView
        }
    }
    
    var macMenu: some View {
        HStack {
            titleView
            
            HStack {
                root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: .bottomTrailing)
                
                toolIconView
                enlargerView
                
                wifiView
            }
            .foregroundStyle(.secondary)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))

            closeFieldView
        }
    }
    
    var tvMenu: some View {
        HStack {
            if isMaster || root.gameModel.gameType != .observer {
                GameDiceToggleButton()
            }
            Spacer()
            wifiView
            closeFieldView
        }
        .focusSectionAll()
    }
    
    var marginWidth: CGFloat {
        appWindowSizeModel.mode == .compact ? 4 : 8
    }
    
    @ViewBuilder
    var titleView: some View {
        if isMaster && appWindowSizeModel.mode == .regular {
            Text(root.gameModel.startGameTime, style: .relative)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Spacer()
        }
    }

    var closeFieldView: some View {
        closeView
            .foregroundStyle(.secondary)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
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
            scenesManager.openWindow(SceneId.logs)
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
#elseif os(visionOS)
        if isMaster {
            toolIconVisionViewMaster
        } else {
            toolIconVisionViewPlayer
        }
#else
        // iOS and tvOS
        if isMaster {
            toolIconIOSViewMaster
        } else {
            toolIconIOSViewPlayer
        }
#endif
    }
    
    @ViewBuilder
    var toolIconMacViewMaster: some View {
        @Bindable var gameScreenModel = gameScreenModel
        GameMainTabButtonView(isMaster: true, displayMode: $gameScreenModel.gameMainTabDisplayMode)
            .padding(.horizontal, marginWidth)
            .onChange(of: gameScreenModel.gameMainTabDisplayMode) { oldValue, newValue in
                handleMainTabDisplayModeChange(oldValue: oldValue, newValue: newValue, isMaster: true)
            }
    }

    @ViewBuilder
    var toolIconMacViewPlayer: some View {
        @Bindable var gameScreenModel = gameScreenModel
        Group {
            if root.gameModel.gameType != .observer {
                GameMainTabButtonView(isMaster: false, displayMode: $gameScreenModel.gameMainTabDisplayMode)
            }
        }
        .padding(.horizontal, marginWidth)
        .onChange(of: gameScreenModel.gameMainTabDisplayMode) { oldValue, newValue in
            handleMainTabDisplayModeChange(oldValue: oldValue, newValue: newValue, isMaster: false)
        }
    }
    
    // MARK: - visionOS Views
    
    @ViewBuilder
    var toolIconVisionViewMaster: some View {
        @Bindable var gameScreenModel = gameScreenModel
        
        firstOptionView
        
        GameMainTabButtonView(isMaster: true, displayMode: $gameScreenModel.gameMainTabDisplayMode)
            .onChange(of: gameScreenModel.gameMainTabDisplayMode) { oldValue, newValue in
                handleMainTabDisplayModeChange(oldValue: oldValue, newValue: newValue, isMaster: true)
            }
    }
    
    @ViewBuilder
    var toolIconVisionViewPlayer: some View {
        @Bindable var gameScreenModel = gameScreenModel
        
        firstOptionView
        
        GameMainTabButtonView(isMaster: false, displayMode: $gameScreenModel.gameMainTabDisplayMode)
            .onChange(of: gameScreenModel.gameMainTabDisplayMode) { oldValue, newValue in
                handleMainTabDisplayModeChange(oldValue: oldValue, newValue: newValue, isMaster: false)
            }
    }
    
    // MARK: - iOS/tvOS Views
    
    @ViewBuilder
    var toolIconIOSViewMaster: some View {
        @Bindable var gameScreenModel = gameScreenModel
        
        // Main game tab button (replaces firstOptionView)
        GameMainTabToggleButtonView(isMaster: true, isShown: $gameScreenModel.showMainTabIOS)
            .onChange(of: gameScreenModel.showMainTabIOS) { oldValue, newValue in
                handleMainTabToggle(isShown: newValue, isMaster: true)
            }
        
        // Settings button
        secondOptionView
    }
    
    @ViewBuilder
    var toolIconIOSViewPlayer: some View {
        @Bindable var gameScreenModel = gameScreenModel
        
        // Main game tab button (replaces firstOptionView)
        GameMainTabToggleButtonView(isMaster: false, isShown: $gameScreenModel.showMainTabIOS)
            .onChange(of: gameScreenModel.showMainTabIOS) { oldValue, newValue in
                handleMainTabToggle(isShown: newValue, isMaster: false)
            }
        
        // Settings button
        secondOptionView
    }
    
    /// Handles the simple show/hide toggle for iOS/tvOS
    func handleMainTabToggle(isShown: Bool, isMaster: Bool) {
        // Save the state to UserDefaults
        if isMaster {
            appSettingsModel.autoShowMasterMainTab = isShown
        } else {
            appSettingsModel.autoShowPlayerMainTab = isShown
        }
        
        // Update the display
        withAnimation {
            if isShown {
                gameScreenModel.showMainTab = isMaster ? .game : .value
            } else {
                gameScreenModel.showMainTab = .none
            }
        }
    }
    
    /// Handles the three-state main tab display mode changes
    func handleMainTabDisplayModeChange(oldValue: GameMainTabDisplayMode, newValue: GameMainTabDisplayMode, isMaster: Bool) {
        // Save the display mode to UserDefaults
        if isMaster {
            appSettingsModel.masterMainTabDisplayMode = newValue.rawValue
        } else {
            appSettingsModel.playerMainTabDisplayMode = newValue.rawValue
        }
        
        switch newValue {
        case .hidden:
            // Hide the game view
            gameScreenModel.showMainTab = .none
            
            // Close the appropriate window if it was open
            if isMaster {
                // Master: Close adventure viewer window
                if scenesManager.getSceneState(for: SceneId.adventureViewer) == .opened {
                    scenesManager.dismissWindow(SceneId.adventureViewer)
                }
            } else {
                // Player: Close character viewer window
                if scenesManager.getSceneState(for: SceneId.valueViewer) == .opened {
                    scenesManager.dismissWindow(SceneId.valueViewer)
                }
            }
            
        case .inline:
            // Show game view inline
            gameScreenModel.showMainTab = isMaster ? .game : .value
            
            // Close the window if it was open
            if isMaster {
                if scenesManager.getSceneState(for: SceneId.adventureViewer) == .opened {
                    scenesManager.dismissWindow(SceneId.adventureViewer)
                }
            } else {
                if scenesManager.getSceneState(for: SceneId.valueViewer) == .opened {
                    scenesManager.dismissWindow(SceneId.valueViewer)
                }
            }
            
        case .window:
            // Hide inline view
            gameScreenModel.showMainTab = .none
            
            // Open as separate window with appropriate content
            #if os(macOS) || os(visionOS)
            if isMaster {
                // Master: Open adventure viewer with current adventure
                if scenesManager.getSceneState(for: SceneId.adventureViewer) == .closed, let adventureId = root.gameModel.selectedAdventure {
                    scenesManager.openWindow(SceneId.viewerId(for: .adventure), selection: WindowItemSelection(itemId: adventureId))
                }
            } else {
                // Player: Open character viewer with current character
                if scenesManager.getSceneState(for: SceneId.valueViewer) == .closed, let characterId = root.gameModel.selectedCharacter {
                    scenesManager.openWindow(SceneId.viewerId(for: .value), selection: WindowItemSelection(itemId: characterId))
                }
            }
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
    
    // MARK: - TableTop Kit Table Volume Button (visionOS only)
    
    @ViewBuilder
    var gameTableButton: some View {
#if os(visionOS)
        @Bindable var gameScreenModel = gameScreenModel
        Button {
            withAnimation {
                appSettingsModel.showGameTableVolume.toggle()
                handleGameTableToggle()
            }
        } label: {
            Image(systemName: "cube.transparent")
                .imageScale(.medium)
        }
        .selectedBorderedStype(isSelected: appSettingsModel.showGameTableVolume)
        .help(appSettingsModel.showGameTableVolume ? "Hide table volume" : "Show table volume")
#else
        EmptyView()
#endif
    }
    
    /// Handles the show/hide of the TableTop Kit table volume (visionOS only)
    func handleGameTableToggle() {
#if os(visionOS)
        if appSettingsModel.showGameTableVolume {
            // Open the table volume
            if scenesManager.getSceneState(for: SceneId.gameTable) != .opened {
                scenesManager.openWindow(SceneId.gameTable)
            }
        } else {
            // Close the table volume
            if scenesManager.getSceneState(for: SceneId.gameTable) != .closed {
                scenesManager.dismissWindow(SceneId.gameTable)
            }
        }
#endif
    }
}

#if os(iOS)
private struct IOSGameOverlayMenu: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool

    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel

    var body: some View {
        GlassEffectContainerAll {
            if appWindowSizeModel.mode == .regular {
                ZStack {
                    HStack(spacing: itemSpacing) {
                        if isMaster || root.gameModel.gameType != .observer {
                            IOSGameDiceToggleButtonField()
                        }
                        if isMaster {
                            IOSGameElapsedTimerText(startDate: root.gameModel.startGameTime)
                        }
                        Spacer()
                        IOSGameSidebarMenu(
                            isMaster: isMaster,
                            allowsPrimaryView: isMaster || root.gameModel.gameType != .observer
                        )
                        IOSGameOverlayCloseButton()
                    }

                    IOSGameOverlayControlField(
                        root: root,
                        playerController: playerController,
                        isMaster: isMaster,
                        spacing: itemSpacing
                    )
                }
            } else {
                HStack(spacing: itemSpacing) {
                    if isMaster || root.gameModel.gameType != .observer {
                        IOSGameDiceToggleButtonField()
                    }
                    Spacer(minLength: 0)
                    IOSGameOverlayControlField(
                        root: root,
                        playerController: playerController,
                        isMaster: isMaster,
                        spacing: itemSpacing
                    )
                    IOSGameSidebarMenu(
                        isMaster: isMaster,
                        allowsPrimaryView: isMaster || root.gameModel.gameType != .observer
                    )
                    IOSGameOverlayCloseButton()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var itemSpacing: CGFloat {
        appWindowSizeModel.mode == .compact ? 4 : 8
    }
}

private struct IOSGameDiceToggleButtonField: View {
    var body: some View {
        GameDiceToggleButton()
            .buttonStyle(.plain)
            .imageScale(.large)
            .padding(8)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

private struct IOSGameElapsedTimerText: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(
                elapsedDuration(at: context.date),
                format: .time(pattern: .hourMinuteSecond(padHourToLength: 2))
            )
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
    }

    private func elapsedDuration(at date: Date) -> Duration {
        let elapsedSeconds = max(0, date.timeIntervalSince(startDate)).rounded(.down)
        return .seconds(elapsedSeconds)
    }
}

private struct IOSGameOverlayControlField: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot)

            if isMaster {
                ControlSharingView(alignment: .bottom, embeddedInGlass: true) {}
                    .zIndex(1)
            }

            if let playerController {
                IOSGameConnectionStatusView(playerController: playerController)
            }
        }
        .buttonStyle(.plain)
        .imageScale(.large)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

private struct IOSGameConnectionStatusView: View {
    let playerController: PlayerController

    var body: some View {
        Label {
            Text(
                playerController.gameModel.lostMaster ? "Connection Lost" : "Connected",
                bundle: .module
            )
        } icon: {
            Image(systemName: playerController.gameModel.lostMaster ? "wifi.slash" : "wifi")
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(playerController.gameModel.lostMaster ? .red : .teal)
        .help(
            Text(
                playerController.gameModel.lostMaster ? "Connection Lost" : "Connected",
                bundle: .module
            )
        )
    }
}

private struct IOSGameSidebarMenu: View {
    let isMaster: Bool
    let allowsPrimaryView: Bool

    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let glass: Glass = if isSidebarVisible {
            .regular.tint(NetworkModules.game.tint.opacity(0.7)).interactive()
        } else {
            .regular.interactive()
        }

        Menu {
            Toggle(isOn: sidebarVisibilityBinding) {
                Label {
                    Text("Sidebar", bundle: .module)
                } icon: {
                    Image(systemName: "sidebar.right")
                }
            }

            Toggle(isOn: primaryViewBinding) {
                Label {
                    Text(currentSidebarViewTitle)
                } icon: {
                    Image(systemName: currentSidebarViewIcon)
                }
            }
            .disabled(!isSidebarVisible || !allowsPrimaryView)

            Button {
                withAnimation {
                    gameScreenModel.toggleSideBarWidth()
                }
            } label: {
                Label {
                    Text(
                        gameScreenModel.isLargeSideBar ? "Reduce Sidebar" : "Enlarge Sidebar",
                        bundle: .module
                    )
                } icon: {
                    Image(
                        systemName: gameScreenModel.isLargeSideBar
                            ? "square.resize.down"
                            : "square.resize.up"
                    )
                }
            }
            .disabled(!isSidebarVisible)
        } label: {
            Label {
                Text("Sidebar", bundle: .module)
            } icon: {
                Image(systemName: "sidebar.right")
                    .symbolVariant(isSidebarVisible ? .fill : .none)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .imageScale(.large)
        .padding(8)
        .contentShape(.circle)
        .glassEffect(glass, in: .circle)
        .help(
            Text(
                isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                bundle: .module
            )
        )
    }

    private var primaryModule: NetworkModules {
        isMaster ? .game : .value
    }

    private var isSidebarVisible: Bool {
        gameScreenModel.showMainTab != .none || gameScreenModel.showSettingTab != .none
    }

    private var isShowingPrimaryView: Bool {
        if gameScreenModel.showMainTab != .none {
            return true
        }

        if gameScreenModel.showSettingTab != .none {
            return false
        }

        return allowsPrimaryView && gameScreenModel.iOSSidebarShowsPrimaryView
    }

    private var currentSidebarViewTitle: String {
        if isShowingPrimaryView {
            return isMaster
                ? String(localized: "Game View", bundle: .module)
                : String(localized: "Character View", bundle: .module)
        }

        return String(localized: "Other View", bundle: .module)
    }

    private var currentSidebarViewIcon: String {
        isShowingPrimaryView ? primaryModule.icon : NetworkModules.setting.icon
    }

    private var sidebarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { isSidebarVisible },
            set: { isVisible in setSidebarVisible(isVisible) }
        )
    }

    private var primaryViewBinding: Binding<Bool> {
        Binding(
            get: { isShowingPrimaryView },
            set: { showsPrimaryView in setPrimaryViewVisible(showsPrimaryView) }
        )
    }

    private func setSidebarVisible(_ isVisible: Bool) {
        gameScreenModel.showMainTabIOS = isVisible

        if isMaster {
            appSettingsModel.autoShowMasterMainTab = isVisible
        } else {
            appSettingsModel.autoShowPlayerMainTab = isVisible
        }

        withAnimation {
            if isVisible {
                showSelectedSidebarView()
            } else {
                gameScreenModel.showMainTab = .none
                gameScreenModel.showSettingTab = .none
            }
        }
    }

    private func setPrimaryViewVisible(_ showsPrimaryView: Bool) {
        guard allowsPrimaryView else { return }
        gameScreenModel.iOSSidebarShowsPrimaryView = showsPrimaryView

        guard isSidebarVisible else { return }

        withAnimation {
            showSelectedSidebarView()
        }
    }

    private func showSelectedSidebarView() {
        if allowsPrimaryView && gameScreenModel.iOSSidebarShowsPrimaryView {
            gameScreenModel.showSettingTab = .none
            gameScreenModel.showMainTab = primaryModule
        } else {
            gameScreenModel.showMainTab = .none
            gameScreenModel.showSettingTab = .setting
        }
    }
}

private struct IOSGameOverlayCloseButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        Button {
            gameScreenModel.showQuitGameAlert = true
        } label: {
            Label {
                Text("Quit", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .labelStyle(.iconOnly)
        }
        .imageScale(.large)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(8)
        .contentShape(.circle)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(Text("Quit", bundle: .module))
    }
}
#endif

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
