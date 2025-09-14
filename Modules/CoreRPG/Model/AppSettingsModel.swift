// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class AppSettingsModel: Sendable {
    public init(showGame: Bool = false) {
        self.showGame = showGame
        initSettings()
    }

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

    // MARK: - Runtime Value only on this device
    
    public var showGame: Bool = false

    // MARK: - Settings Value only on this device

    public var firstLaunch: Bool = true {
        didSet {
            guard oldValue != firstLaunch else { return }
            UserDefaults.standard.set(firstLaunch, forKey: AppSettingsModel.firstLunchKey)
        }
    }
    
    public var appColorScheme: AppColorScheme = .system {
        didSet {
            guard oldValue != appColorScheme else { return }
            UserDefaults.standard.set(appColorScheme.rawValue, forKey: AppSettingsModel.appColorSchemeKey)
        }
    }

    // MARK: - Init Settings
    
    private func initSettings() {
        firstLaunch = UserDefaults.standard.value(forKey: AppSettingsModel.firstLunchKey) as? Bool ?? true
        appColorScheme = AppColorScheme(rawValue: UserDefaults.standard.integer(forKey: AppSettingsModel.appColorSchemeKey)) ?? .system
    }

    // MARK: - Keys

    private static let firstLunchKey = "FirstLunchMasterRPG"
    private static let appColorSchemeKey = "appColorScheme"
}

public extension View {
    func resetAppColorScheme() -> some View {
        modifier(AppColorSchemeReset())
    }
}

struct AppColorSchemeReset: ViewModifier {
    @Environment(AppSettingsModel.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
#if os(iOS)
            .environment(\.colorScheme, settings.appColorScheme.colorScheme(for: colorScheme))
#endif
    }
}
