// @copyright André Trettin

import Observation
import SwiftUI

@MainActor @Observable
public final class AppSettingsModel: Sendable {
    public init() {
        self.defaults = .standard
        initSettings(from: .standard)
    }

    private init(previewValues: PreviewValues) {
        self.defaults = nil
        firstLaunch = previewValues.firstLaunch
        appColorScheme = previewValues.appColorScheme
        autoShowMasterMainTab = previewValues.autoShowMasterMainTab
        autoShowPlayerMainTab = previewValues.autoShowPlayerMainTab
        masterMainTabDisplayMode = previewValues.masterMainTabDisplayMode
        playerMainTabDisplayMode = previewValues.playerMainTabDisplayMode
        showGameTableVolume = previewValues.showGameTableVolume
        needsValidateDatabase = previewValues.needsValidateDatabase
        useCloudKit = previewValues.useCloudKit
    }

    private let defaults: UserDefaults?

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
            defaults?.set(firstLaunch, forKey: AppSettingsModel.firstLunchKey)
        }
    }
    
    public var appColorScheme: AppColorScheme = .system {
        didSet {
            guard oldValue != appColorScheme else { return }
            defaults?.set(appColorScheme.rawValue, forKey: AppSettingsModel.appColorSchemeKey)
        }
    }
    
    public var autoShowMasterMainTab: Bool = true {
        didSet {
            guard oldValue != autoShowMasterMainTab else { return }
            defaults?.set(autoShowMasterMainTab, forKey: AppSettingsModel.autoShowMasterMainTabKey)
        }
    }
    
    public var autoShowPlayerMainTab: Bool = true {
        didSet {
            guard oldValue != autoShowPlayerMainTab else { return }
            defaults?.set(autoShowPlayerMainTab, forKey: AppSettingsModel.autoShowPlayerMainTabKey)
        }
    }
    
    public var masterMainTabDisplayMode: Int = 0 {
        didSet {
            guard oldValue != masterMainTabDisplayMode else { return }
            defaults?.set(masterMainTabDisplayMode, forKey: AppSettingsModel.masterMainTabDisplayModeKey)
        }
    }
    
    public var playerMainTabDisplayMode: Int = 0 {
        didSet {
            guard oldValue != playerMainTabDisplayMode else { return }
            defaults?.set(playerMainTabDisplayMode, forKey: AppSettingsModel.playerMainTabDisplayModeKey)
        }
    }
    
    public var showGameTableVolume: Bool = false {
        didSet {
            guard oldValue != showGameTableVolume else { return }
            defaults?.set(showGameTableVolume, forKey: AppSettingsModel.showGameTableVolumeKey)
        }
    }

    public var needsValidateDatabase: Bool = true {
        didSet {
            guard oldValue != needsValidateDatabase else { return }
            defaults?.set(needsValidateDatabase, forKey: AppSettingsModel.needsValidateDatabaseKey)
        }
    }

    // MARK: - Shared Settings Value in AppGroups
    
    public private(set) var useCloudKit: Bool = false {
        didSet {
            guard oldValue != useCloudKit else { return }
            defaults?.set(useCloudKit, forKey: AppSettingsModel.useCloudKitKey)
        }
    }
    
    // MARK: - Reset function
    
    public func resetCloudKit(to newValue: Bool) {
        guard useCloudKit != newValue else { return }
        useCloudKit = newValue
    }
    
    // MARK: - Init Settings
    
    private func initSettings(from defaults: UserDefaults) {
        firstLaunch = defaults.value(forKey: AppSettingsModel.firstLunchKey) as? Bool ?? true
        appColorScheme = AppColorScheme(rawValue: defaults.integer(forKey: AppSettingsModel.appColorSchemeKey)) ?? .system
        
        autoShowMasterMainTab = defaults.value(forKey: AppSettingsModel.autoShowMasterMainTabKey) as? Bool ?? true
        autoShowPlayerMainTab = defaults.value(forKey: AppSettingsModel.autoShowPlayerMainTabKey) as? Bool ?? true
        
        masterMainTabDisplayMode = defaults.integer(forKey: AppSettingsModel.masterMainTabDisplayModeKey)
        playerMainTabDisplayMode = defaults.integer(forKey: AppSettingsModel.playerMainTabDisplayModeKey)
        
        showGameTableVolume = defaults.bool(forKey: AppSettingsModel.showGameTableVolumeKey)
        needsValidateDatabase = defaults.value(forKey: AppSettingsModel.needsValidateDatabaseKey) as? Bool ?? true

        // shared App groups
        useCloudKit = defaults.bool(forKey: AppSettingsModel.useCloudKitKey)
    }

    public static func previewFixture(
        firstLaunch: Bool = false,
        appColorScheme: AppColorScheme = .system,
        useCloudKit: Bool = false
    ) -> AppSettingsModel {
        AppSettingsModel(
            previewValues: PreviewValues(
                firstLaunch: firstLaunch,
                appColorScheme: appColorScheme,
                useCloudKit: useCloudKit
            )
        )
    }

    private struct PreviewValues {
        var firstLaunch = false
        var appColorScheme: AppColorScheme = .system
        var autoShowMasterMainTab = true
        var autoShowPlayerMainTab = true
        var masterMainTabDisplayMode = 0
        var playerMainTabDisplayMode = 0
        var showGameTableVolume = false
        var needsValidateDatabase = false
        var useCloudKit = false
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
