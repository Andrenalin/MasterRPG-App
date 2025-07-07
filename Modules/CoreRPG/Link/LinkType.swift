// @copyright André Trettin

import Foundation

public enum LinkType: String, Equatable, Hashable, Sendable, CaseIterable {
    case photoImmersive
    case play
    case remove
    case roll
    case share
    case show
    
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .photoImmersive: "Immersive"
        case .play: "Play"
        case .remove: "Remove"
        case .roll: "Roll"
        case .share: "Share"
        case .show: "Show"
        }
    }
    
    var title: String {
        String(localized: localizedTitle).localizedString
    }
    
    var icon: String {
        switch self {
        case .photoImmersive: "photo.fill"
        case .play: "play.fill"
        case .remove: "trash.fill"
        case .roll: "dice.fill"
        case .share: "square.and.arrow.up.fill"
        case .show: "eye.fill"
        }
    }
    
    public var linkNumberAddition: Int {
        switch self {
        case .photoImmersive: 100
        case .play: 200
        case .remove: 300
        case .roll: 400
        case .share: 500
        case .show: 600
        }
    }
}
