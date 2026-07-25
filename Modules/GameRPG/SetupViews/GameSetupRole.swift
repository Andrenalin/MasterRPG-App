// @copyright André Trettin

import CoreRPG
import SwiftUI

enum GameSetupRole: Int, CaseIterable, Hashable, Identifiable {
#if !os(tvOS)
    case player = 0
    case master = 1
#endif
    case join = 2

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
#if !os(tvOS)
        case .player:
            LocalizedStringResource("Player", bundle: .module)
        case .master:
            LocalizedStringResource("Game Master", bundle: .module)
#endif
        case .join:
            LocalizedStringResource("Join", bundle: .module)
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
#if !os(tvOS)
        case .player:
            LocalizedStringResource("Choose a character and join a shared game.", bundle: .module)
        case .master:
            LocalizedStringResource("Choose an adventure and host the session.", bundle: .module)
#endif
        case .join:
            LocalizedStringResource("Find a nearby game as observer or proxy.", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
#if !os(tvOS)
        case .player: "theatermasks.fill"
        case .master: "wand.and.stars"
#endif
        case .join: "person.2.wave.2.fill"
        }
    }

    static var previewPlayer: GameSetupRole {
#if os(tvOS)
        .join
#else
        .player
#endif
    }

    static var previewMaster: GameSetupRole {
#if os(tvOS)
        .join
#else
        .master
#endif
    }
}
