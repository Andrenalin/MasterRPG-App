// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SelectorView: View {
    let root: GameRoot
    
    enum GameType: Int, Hashable, CaseIterable, Identifiable {
#if !os(tvOS)
        case player = 0
        case master = 1
#endif
        case proxy = 2
        
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
                return "Join"
            }
        }
    }
    
#if os(tvOS)
    @AppStorage("lastSelectedGameType", store: .standard)
    private var selected: GameType = .proxy
#else
    @AppStorage("lastSelectedGameType", store: .standard)
    private var selected: GameType = .player
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
            
            Group {
                switch selected {
#if !os(tvOS)
                case .player:
                    playerView
                case .master:
                    gameMasterView
#endif
                case .proxy:
                    proxyView
                }
            }
        }
    }
    
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
                SelectedAdventureView(root: root)
                MasterStartView(root: root)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var proxyView: some View {
        SearchProxyView(root: root)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        SelectorView(root: .preview)
    }
}
