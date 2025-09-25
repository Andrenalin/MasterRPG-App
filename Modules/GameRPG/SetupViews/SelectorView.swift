// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SelectorView: View {
    let root: GameRootController
    
    @AppStorage("lastSelectedGameType", store: .standard)
    private var gameTypeInt: Int = 0
    
    enum GameType: Int, Hashable, CaseIterable, Identifiable {
        #if !os(tvOS)
        case player = 0
        case master = 1
        #endif
        case proxy = 2
        case observer = 3
        
        var id: Int { rawValue }
        var text: LocalizedStringKey {
            switch self {
#if !os(tvOS)
            case .player:
                return "Player"
            case .master:
                return "Master"
#endif
            case .proxy:
                return "Proxy"
            case .observer:
                return "Observer"
            }
        }
    }
#if !os(tvOS)
    @State private var selected: GameType = .player
#else
    @State private var selected: GameType = .proxy
#endif
    
    var body: some View {
        VStack {
            Picker(selection: $selected) {
                ForEach(GameType.allCases) { gameType in
                    Text(gameType.text, bundle: .module)
                        .tag(gameType)
                }
            } label: {
                Text("Choose", bundle: .module)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            ZStack(alignment: .top) {
                switch selected {
#if !os(tvOS)
                case .player:
                    playerView
                case .master:
                    gameMasterView
#endif
                case .proxy:
                    proxyView
                case .observer:
                    observerView
                }
            }
        }
        .onAppear {
#if !os(tvOS)
            withAnimation { selected <=> GameType(rawValue: gameTypeInt) ?? .player }
#else
            withAnimation { selected <=> GameType(rawValue: gameTypeInt) ?? .proxy }
#endif
        }
        .onChange(of: selected) {
            gameTypeInt <=> selected.rawValue
        }
    }
    
    @MainActor
    private var playerView: some View {
        ScrollView {
            VStack {
                SelectedPlayerView(root: root)
                
                PlayerStartView(root: root)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var gameMasterView: some View {
        ScrollView {
            VStack {
                SelectedMasterView(root: root)
                
                SelectedAdventureView(root: root)
                
                MasterStartView(root: root)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var observerView: some View {
        ScrollView {
            SelectObserverGameView(root: root)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var proxyView: some View {
        ScrollView {
            SearchProxyView(root: root)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SelectorView(root: .preview)
        .environment(AppSettingsModel())
}
