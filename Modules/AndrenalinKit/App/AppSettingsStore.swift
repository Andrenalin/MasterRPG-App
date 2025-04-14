// @copyright André Trettin

import Observation
import SwiftUI

@MainActor @Observable
public final class AppSettingsModel: Sendable {
    public enum AppColorScheme: Int, Hashable, CaseIterable, Identifiable, Codable {
        public var id: Int {
            rawValue
        }

        case system
        case dark
        case light

        public func colorScheme(for system: ColorScheme) -> ColorScheme {
            switch self {
            case .system:
                return system
            case .dark:
                return .dark
            case .light:
                return .light
            }
        }
    }

    public var gameModus: GameModus = .edit
    public var showGame: Bool = false
    public var appColorScheme: AppColorScheme = .system
    public var useCloudKit: Bool = true

    public init(gameModus: GameModus = .edit, showGame: Bool = false) {
        self.gameModus = gameModus
        self.showGame = showGame
    }

    public var showGameActions: ShowGameActions {
        ShowGameActions(show: { @MainActor [weak self] in self?.showGame = $0 })
    }
}
