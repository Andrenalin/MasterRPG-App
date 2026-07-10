// @copyright André Trettin

import Observation
import SwiftUI

@MainActor @Observable
public final class AppSettingsModel: Sendable {
    public init() {
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
    
    public var autoShowMasterMainTab: Bool = true {
        didSet {
            guard oldValue != autoShowMasterMainTab else { return }
            UserDefaults.standard.set(autoShowMasterMainTab, forKey: AppSettingsModel.autoShowMasterMainTabKey)
        }
    }
    
    public var autoShowPlayerMainTab: Bool = true {
        didSet {
            guard oldValue != autoShowPlayerMainTab else { return }
            UserDefaults.standard.set(autoShowPlayerMainTab, forKey: AppSettingsModel.autoShowPlayerMainTabKey)
        }
    }
    
    public var masterMainTabDisplayMode: Int = 0 {
        didSet {
            guard oldValue != masterMainTabDisplayMode else { return }
            UserDefaults.standard.set(masterMainTabDisplayMode, forKey: AppSettingsModel.masterMainTabDisplayModeKey)
        }
    }
    
    public var playerMainTabDisplayMode: Int = 0 {
        didSet {
            guard oldValue != playerMainTabDisplayMode else { return }
            UserDefaults.standard.set(playerMainTabDisplayMode, forKey: AppSettingsModel.playerMainTabDisplayModeKey)
        }
    }
    
    public var showGameTableVolume: Bool = false {
        didSet {
            guard oldValue != showGameTableVolume else { return }
            UserDefaults.standard.set(showGameTableVolume, forKey: AppSettingsModel.showGameTableVolumeKey)
        }
    }

    public var needsValidateDatabase: Bool = true {
        didSet {
            guard oldValue != needsValidateDatabase else { return }
            UserDefaults.standard.set(needsValidateDatabase, forKey: AppSettingsModel.needsValidateDatabaseKey)
        }
    }

    // MARK: - Shared Settings Value in AppGroups
    
    public private(set) var useCloudKit: Bool = false {
        didSet {
            guard oldValue != useCloudKit else { return }
            UserDefaults.standard.set(useCloudKit, forKey: AppSettingsModel.useCloudKitKey)
        }
    }
    
    // MARK: - Reset function
    
    public func resetCloudKit(to newValue: Bool) {
        guard useCloudKit != newValue else { return }
        useCloudKit = newValue
    }
    
    // MARK: - Init Settings
    
    private func initSettings() {
        firstLaunch = UserDefaults.standard.value(forKey: AppSettingsModel.firstLunchKey) as? Bool ?? true
        appColorScheme = AppColorScheme(rawValue: UserDefaults.standard.integer(forKey: AppSettingsModel.appColorSchemeKey)) ?? .system
        
        autoShowMasterMainTab = UserDefaults.standard.value(forKey: AppSettingsModel.autoShowMasterMainTabKey) as? Bool ?? true
        autoShowPlayerMainTab = UserDefaults.standard.value(forKey: AppSettingsModel.autoShowPlayerMainTabKey) as? Bool ?? true
        
        masterMainTabDisplayMode = UserDefaults.standard.integer(forKey: AppSettingsModel.masterMainTabDisplayModeKey)
        playerMainTabDisplayMode = UserDefaults.standard.integer(forKey: AppSettingsModel.playerMainTabDisplayModeKey)
        
        showGameTableVolume = UserDefaults.standard.bool(forKey: AppSettingsModel.showGameTableVolumeKey)
        needsValidateDatabase = UserDefaults.standard.value(forKey: AppSettingsModel.needsValidateDatabaseKey) as? Bool ?? true

        // shared App groups
        useCloudKit = UserDefaults.standard.bool(forKey: AppSettingsModel.useCloudKitKey)
    }
    
    // MARK: - Keys
    
    private static let migrationKey = "MasterRPGMigrationAppGroup"
    private static let firstLunchKey = "FirstLunchMasterRPG"
    private static let appColorSchemeKey = "appColorScheme"
    private static let autoShowMasterMainTabKey = "autoShowMasterMainTab"
    private static let autoShowPlayerMainTabKey = "autoShowPlayerMainTab"
    private static let masterMainTabDisplayModeKey = "masterMainTabDisplayMode"
    private static let playerMainTabDisplayModeKey = "playerMainTabDisplayMode"
    private static let showGameTableVolumeKey = "showGameTableVolume"
    private static let needsValidateDatabaseKey = "needsValidate"

    private static let useCloudKitKey = "MasterRPGuseCloudKit"
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
