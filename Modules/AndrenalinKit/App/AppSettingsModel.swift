// @copyright André Trettin

import Observation
import SwiftUI

@MainActor @Observable
public final class AppSettingsModel: Sendable {
    public init(gameModus: GameModus = .edit, showGame: Bool = false) {
        self.gameModus = gameModus
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
    
    public var gameModus: GameModus = .edit
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

    // MARK: - Shared Settings Value in AppGroups
    
    public private(set) var useCloudKit: Bool = false {
        didSet {
            guard oldValue != useCloudKit else { return }
            UserDefaults.appGroup.set(useCloudKit, forKey: AppSettingsModel.useCloudKitKey)
        }
    }

    public var defaultAudioLocation: Int = 0 {
        didSet {
            guard oldValue != defaultAudioLocation else { return }
            UserDefaults.appGroup.set(defaultAudioLocation, forKey: AppSettingsModel.defaultAudioLocationKey)
        }
    }
    public var defaultAudioPath: String? {
        didSet {
            guard oldValue != defaultAudioPath else { return }
            UserDefaults.appGroup.set(defaultAudioPath, forKey: AppSettingsModel.defaultAudioPathKey)
        }
    }
    
    public var defaultPdfLocation: Int = 0 {
        didSet {
            guard oldValue != defaultPdfLocation else { return }
            UserDefaults.appGroup.set(defaultPdfLocation, forKey: AppSettingsModel.defaultPdfLocationKey)
        }
    }
    public var defaultPdfPath: String? {
        didSet {
            guard oldValue != defaultPdfPath else { return }
            UserDefaults.appGroup.set(defaultPdfPath, forKey: AppSettingsModel.defaultPdfPathKey)
        }
    }
    
    public var defaultPhotoLocation: Int = 0 {
        didSet {
            guard oldValue != defaultPhotoLocation else { return }
            UserDefaults.appGroup.set(defaultPhotoLocation, forKey: AppSettingsModel.defaultPhotoLocationKey)
        }
    }
    public var defaultPhotoPath: String? {
        didSet {
            guard oldValue != defaultPhotoPath else { return }
            UserDefaults.appGroup.set(defaultPhotoPath, forKey: AppSettingsModel.defaultPhotoPathKey)
        }
    }
    
    public var defaultSpaceLocation: Int = 0 {
        didSet {
            guard oldValue != defaultSpaceLocation else { return }
            UserDefaults.appGroup.set(defaultSpaceLocation, forKey: AppSettingsModel.defaultSpaceLocationKey)
        }
    }
    public var defaultSpacePath: String? {
        didSet {
            guard oldValue != defaultSpacePath else { return }
            UserDefaults.appGroup.set(defaultSpacePath, forKey: AppSettingsModel.defaultSpacePathKey)
        }
    }
    
    // MARK: - Reset function
    
    public func resetCloudKit(to newValue: Bool) {
        guard useCloudKit != newValue else { return }
        useCloudKit = newValue
        guard useCloudKit else { return }
        if defaultAudioLocation == FileLocation.local.rawValue {
            defaultAudioLocation = FileLocation.appCloud.rawValue
        }
        if defaultPdfLocation == FileLocation.local.rawValue {
            defaultPdfLocation = FileLocation.appCloud.rawValue
        }
        if defaultPhotoLocation == FileLocation.local.rawValue {
            defaultPhotoLocation = FileLocation.appCloud.rawValue
        }
        if defaultSpaceLocation == FileLocation.local.rawValue {
            defaultSpaceLocation = FileLocation.appCloud.rawValue
        }
    }
    
    // MARK: - Others
    
    public var showGameActions: ShowGameActions {
        ShowGameActions(show: { @MainActor [weak self] in self?.showGame = $0 })
    }
        
    // MARK: - Init Settings
    
    private func initSettings() {
        let migration = UserDefaults.appGroup.bool(forKey: AppSettingsModel.migrationKey)
        if migration == false {
            migrateSettings()
            UserDefaults.appGroup.set(true, forKey: AppSettingsModel.migrationKey)
        }

        firstLaunch = UserDefaults.standard.value(forKey: AppSettingsModel.firstLunchKey) as? Bool ?? true
        appColorScheme = AppColorScheme(rawValue: UserDefaults.standard.integer(forKey: AppSettingsModel.appColorSchemeKey)) ?? .system
        
        // shared App groups
        useCloudKit = UserDefaults.appGroup.bool(forKey: AppSettingsModel.useCloudKitKey)
        
        defaultAudioLocation = UserDefaults.appGroup.integer(forKey: AppSettingsModel.defaultAudioLocationKey)
        defaultAudioPath = UserDefaults.appGroup.string(forKey: AppSettingsModel.defaultAudioPathKey)

        defaultPdfLocation = UserDefaults.appGroup.integer(forKey: AppSettingsModel.defaultPdfLocationKey)
        defaultPdfPath = UserDefaults.appGroup.string(forKey: AppSettingsModel.defaultPdfPathKey)

        defaultPhotoLocation = UserDefaults.appGroup.integer(forKey: AppSettingsModel.defaultPhotoLocationKey)
        defaultPhotoPath = UserDefaults.appGroup.string(forKey: AppSettingsModel.defaultPhotoPathKey)
        
        defaultSpaceLocation = UserDefaults.appGroup.integer(forKey: AppSettingsModel.defaultSpaceLocationKey)
        defaultSpacePath = UserDefaults.appGroup.string(forKey: AppSettingsModel.defaultSpacePathKey)
    }
    
    // MARK: - Migrate Settings
    
    private func migrateSettings() {
        let useCloudKit = UserDefaults.standard.bool(forKey: AppSettingsModel.useCloudKitKey)
        UserDefaults.appGroup.set(useCloudKit, forKey: AppSettingsModel.useCloudKitKey)
        
        var defaultLocation = UserDefaults.standard.integer(forKey: AppSettingsModel.defaultAudioLocationKey)
        UserDefaults.appGroup.set(defaultLocation, forKey: AppSettingsModel.defaultAudioLocationKey)
        var defaultPath = UserDefaults.standard.string(forKey: AppSettingsModel.defaultAudioPathKey)
        UserDefaults.appGroup.set(defaultPath, forKey: AppSettingsModel.defaultAudioPathKey)
        
        defaultLocation = UserDefaults.standard.integer(forKey: AppSettingsModel.defaultPdfLocationKey)
        UserDefaults.appGroup.set(defaultLocation, forKey: AppSettingsModel.defaultPdfLocationKey)
        defaultPath = UserDefaults.standard.string(forKey: AppSettingsModel.defaultPdfPathKey)
        UserDefaults.appGroup.set(defaultPath, forKey: AppSettingsModel.defaultPdfPathKey)

        defaultLocation = UserDefaults.standard.integer(forKey: AppSettingsModel.defaultPhotoLocationKey)
        UserDefaults.appGroup.set(defaultLocation, forKey: AppSettingsModel.defaultPhotoLocationKey)
        defaultPath = UserDefaults.standard.string(forKey: AppSettingsModel.defaultPhotoPathKey)
        UserDefaults.appGroup.set(defaultPath, forKey: AppSettingsModel.defaultPhotoPathKey)

        defaultLocation = UserDefaults.standard.integer(forKey: AppSettingsModel.defaultSpaceLocationKey)
        UserDefaults.appGroup.set(defaultLocation, forKey: AppSettingsModel.defaultSpaceLocationKey)
        defaultPath = UserDefaults.standard.string(forKey: AppSettingsModel.defaultSpacePathKey)
        UserDefaults.appGroup.set(defaultPath, forKey: AppSettingsModel.defaultSpacePathKey)
    }

    // MARK: - Keys
    
    private static let migrationKey = "MasterRPGMigrationAppGroup"
    private static let firstLunchKey = "FirstLunchMasterRPG"
    private static let appColorSchemeKey = "appColorScheme"

    private static let useCloudKitKey = "MasterRPGuseCloudKit"
    
    private static let defaultAudioLocationKey = "defaultAudioLocation"
    private static let defaultAudioPathKey = "defaultAudioPath"

    private static let defaultPdfLocationKey = "defaultPdfLocation"
    private static let defaultPdfPathKey = "defaultPdfPath"

    private static let defaultPhotoLocationKey = "defaultPhotoLocation"
    private static let defaultPhotoPathKey = "defaultPhotoPath"

    private static let defaultSpaceLocationKey = "defaultSpaceLocation"
    private static let defaultSpacePathKey = "defaultSpacePath"
}
