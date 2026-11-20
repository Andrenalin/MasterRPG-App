// @copyright André Trettin

import Observation
import SwiftUI

@MainActor @Observable
public final class AppSettingsModel: Sendable {
    public init() {
        self.defaults = .standard
        initSettings(from: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        initSettings(from: defaults)
    }

    private init(previewValues: PreviewValues) {
        self.defaults = nil
        firstLaunch = previewValues.firstLaunch
        appColorScheme = previewValues.appColorScheme
        appThemeID = previewValues.appThemeID
        recentThemeIDs = [previewValues.appThemeID]
        autoShowMasterMainTab = previewValues.autoShowMasterMainTab
        autoShowPlayerMainTab = previewValues.autoShowPlayerMainTab
        masterMainTabDisplayMode = previewValues.masterMainTabDisplayMode
        playerMainTabDisplayMode = previewValues.playerMainTabDisplayMode
        showGameTableVolume = previewValues.showGameTableVolume
        showGameDice = previewValues.showGameDice
        showGamePlayerDice = previewValues.showGamePlayerDice
        showGameQuickDice = previewValues.showGameQuickDice
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
            defaults?.set(firstLaunch, forKey: AppSettingsModel.firstLaunchKey)
        }
    }
    
    public var appColorScheme: AppColorScheme = .system {
        didSet {
            guard oldValue != appColorScheme else { return }
            defaults?.set(appColorScheme.rawValue, forKey: AppSettingsModel.appColorSchemeKey)
        }
    }

    public var appThemeID: AppThemeID = .standard {
        didSet {
            guard oldValue != appThemeID else { return }
            defaults?.set(appThemeID.rawValue, forKey: AppSettingsModel.appThemeIDKey)
            recordRecentTheme(appThemeID)
        }
    }

    public private(set) var recentThemeIDs: [AppThemeID] = []
    
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
    
    /// The game master's sidebar layout on iPad, raw `GameSidebarLayout` (0 single, 1 horizontal,
    /// 2 vertical). Stored as an `Int` like the main tab display modes, since the enum lives in GameRPG.
    public var masterSidebarLayout: Int = 0 {
        didSet {
            guard oldValue != masterSidebarLayout else { return }
            defaults?.set(masterSidebarLayout, forKey: AppSettingsModel.masterSidebarLayoutKey)
        }
    }

    public var showGameTableVolume: Bool = false {
        didSet {
            guard oldValue != showGameTableVolume else { return }
            defaults?.set(showGameTableVolume, forKey: AppSettingsModel.showGameTableVolumeKey)
        }
    }

    public var showGameDice: Bool = true {
        didSet {
            guard oldValue != showGameDice else { return }
            defaults?.set(showGameDice, forKey: AppSettingsModel.showGameDiceKey)
        }
    }

    public var showGamePlayerDice: Bool = true {
        didSet {
            guard oldValue != showGamePlayerDice else { return }
            defaults?.set(showGamePlayerDice, forKey: AppSettingsModel.showGamePlayerDiceKey)
        }
    }

    public var showGameQuickDice: Bool = false {
        didSet {
            guard oldValue != showGameQuickDice else { return }
            defaults?.set(showGameQuickDice, forKey: AppSettingsModel.showGameQuickDiceKey)
        }
    }

    public var needsValidateDatabase: Bool = true {
        didSet {
            guard oldValue != needsValidateDatabase else { return }
            defaults?.set(needsValidateDatabase, forKey: AppSettingsModel.needsValidateDatabaseKey)
        }
    }

    // MARK: - Shared Settings Value in AppGroups

    // `useCloudKit` is persisted to `UserDefaults.appGroup`, not `.standard` — it must be
    // readable from the Share Extension process (see `readUseCloudKitFromDefaults()`), which
    // has its own sandboxed `.standard` domain that never sees values the main app writes to
    // its own `.standard`. Writing here to `.standard` used to make the extension permanently
    // believe CloudKit sync was off, no matter the user's actual setting. See CODE_AUDIT §5.2.
    public private(set) var useCloudKit: Bool = false {
        didSet {
            guard oldValue != useCloudKit else { return }
            UserDefaults.appGroup?.set(useCloudKit, forKey: AppSettingsModel.useCloudKitKey)
        }
    }

    // MARK: - Reset function

    public func resetCloudKit(to newValue: Bool) {
        guard useCloudKit != newValue else { return }
        useCloudKit = newValue
    }

    /// Reads the persisted `useCloudKit` value directly from the shared App Group defaults,
    /// without constructing an `AppSettingsModel` (or anything that owns one, such as `AppModel`).
    ///
    /// Intended for lightweight call sites — like the Share Extension — that need this single
    /// value but must not pay the cost of building the full app object graph to get it. Must
    /// read the same `UserDefaults.appGroup` domain the main app writes to above, not `.standard`
    /// — see CODE_AUDIT §5.2.
    public static func readUseCloudKitFromDefaults() -> Bool {
        UserDefaults.appGroup?.bool(forKey: useCloudKitKey) ?? false
    }
    
    // MARK: - Init Settings
    
    private func initSettings(from defaults: UserDefaults) {
        firstLaunch = defaults.value(forKey: AppSettingsModel.firstLaunchKey) as? Bool ?? true
        appColorScheme = AppColorScheme(rawValue: defaults.integer(forKey: AppSettingsModel.appColorSchemeKey)) ?? .system
        recentThemeIDs = defaults.stringArray(forKey: AppSettingsModel.recentThemeIDsKey)?
            .compactMap(AppThemeID.init(rawValue:)) ?? []
        appThemeID = defaults.string(forKey: AppSettingsModel.appThemeIDKey)
            .flatMap(AppThemeID.init(rawValue:)) ?? .standard
        recordRecentTheme(appThemeID)
        
        autoShowMasterMainTab = defaults.value(forKey: AppSettingsModel.autoShowMasterMainTabKey) as? Bool ?? true
        autoShowPlayerMainTab = defaults.value(forKey: AppSettingsModel.autoShowPlayerMainTabKey) as? Bool ?? true
        
        masterMainTabDisplayMode = defaults.integer(forKey: AppSettingsModel.masterMainTabDisplayModeKey)
        playerMainTabDisplayMode = defaults.integer(forKey: AppSettingsModel.playerMainTabDisplayModeKey)
        masterSidebarLayout = defaults.integer(forKey: AppSettingsModel.masterSidebarLayoutKey)
        
        showGameTableVolume = defaults.bool(forKey: AppSettingsModel.showGameTableVolumeKey)
        showGameDice = defaults.value(forKey: AppSettingsModel.showGameDiceKey) as? Bool ?? true
        showGamePlayerDice = defaults.value(forKey: AppSettingsModel.showGamePlayerDiceKey) as? Bool ?? true
        showGameQuickDice = defaults.value(forKey: AppSettingsModel.showGameQuickDiceKey) as? Bool ?? false
        needsValidateDatabase = defaults.value(forKey: AppSettingsModel.needsValidateDatabaseKey) as? Bool ?? true

        // Shared across processes (main app + Share Extension) — always read from the App
        // Group domain, not the `defaults` this instance was otherwise constructed with, so
        // every process observes the same value. See CODE_AUDIT §5.2.
        useCloudKit = UserDefaults.appGroup?.bool(forKey: AppSettingsModel.useCloudKitKey) ?? false
    }

    public static func previewFixture(
        firstLaunch: Bool = false,
        appColorScheme: AppColorScheme = .system,
        appThemeID: AppThemeID = .standard,
        showGameDice: Bool = true,
        showGamePlayerDice: Bool = true,
        useCloudKit: Bool = false
    ) -> AppSettingsModel {
        AppSettingsModel(
            previewValues: PreviewValues(
                firstLaunch: firstLaunch,
                appColorScheme: appColorScheme,
                appThemeID: appThemeID,
                showGameDice: showGameDice,
                showGamePlayerDice: showGamePlayerDice,
                useCloudKit: useCloudKit
            )
        )
    }

    private struct PreviewValues {
        var firstLaunch = false
        var appColorScheme: AppColorScheme = .system
        var appThemeID: AppThemeID = .standard
        var autoShowMasterMainTab = true
        var autoShowPlayerMainTab = true
        var masterMainTabDisplayMode = 0
        var playerMainTabDisplayMode = 0
        var showGameTableVolume = false
        var showGameDice = true
        var showGamePlayerDice = true
        var showGameQuickDice = false
        var needsValidateDatabase = false
        var useCloudKit = false
    }
    
    // MARK: - Keys
    
    /// The stored key keeps its historic spelling: renaming it would reset the flag on every
    /// installed device. See CODE_AUDIT_21 §9.9.
    private static let firstLaunchKey = "FirstLunchMasterRPG"
    private static let appColorSchemeKey = "appColorScheme"
    private static let appThemeIDKey = "appThemeID"
    private static let recentThemeIDsKey = "recentThemeIDs"
    private static let autoShowMasterMainTabKey = "autoShowMasterMainTab"
    private static let autoShowPlayerMainTabKey = "autoShowPlayerMainTab"
    private static let masterMainTabDisplayModeKey = "masterMainTabDisplayMode"
    private static let playerMainTabDisplayModeKey = "playerMainTabDisplayMode"
    private static let masterSidebarLayoutKey = "masterSidebarLayout"
    private static let showGameTableVolumeKey = "showGameTableVolume"
    private static let showGameDiceKey = "showGameDice"
    private static let showGamePlayerDiceKey = "showGamePlayerDice"
    private static let showGameQuickDiceKey = "showGameQuickDice"
    private static let needsValidateDatabaseKey = "needsValidate"

    private static let useCloudKitKey = "MasterRPGuseCloudKit"

    private func recordRecentTheme(_ themeID: AppThemeID) {
        let updatedThemes = [themeID] + recentThemeIDs.filter { $0 != themeID }
        recentThemeIDs = Array(updatedThemes.prefix(3))
        defaults?.set(recentThemeIDs.map(\.rawValue), forKey: AppSettingsModel.recentThemeIDsKey)
    }
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
