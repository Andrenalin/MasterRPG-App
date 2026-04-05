// @copyright André Trettin

import Observation
import SwiftUI

@MainActor @Observable
public final class AppSettingsModel: Sendable {
    public init(gameModus: GameModus = .edit) {
        self.gameModus = gameModus
        
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
            UserDefaults.standard.set(useCloudKit, forKey: AppSettingsModel.useCloudKitKey)
        }
    }

    public var defaultAudioLocation: Int = 0 {
        didSet {
            guard oldValue != defaultAudioLocation else { return }
            UserDefaults.standard.set(defaultAudioLocation, forKey: AppSettingsModel.defaultAudioLocationKey)
        }
    }
    public var defaultAudioPath: String? {
        didSet {
            guard oldValue != defaultAudioPath else { return }
            UserDefaults.standard.set(defaultAudioPath, forKey: AppSettingsModel.defaultAudioPathKey)
        }
    }
    
    public var defaultPdfLocation: Int = 0 {
        didSet {
            guard oldValue != defaultPdfLocation else { return }
            UserDefaults.standard.set(defaultPdfLocation, forKey: AppSettingsModel.defaultPdfLocationKey)
        }
    }
    public var defaultPdfPath: String? {
        didSet {
            guard oldValue != defaultPdfPath else { return }
            UserDefaults.standard.set(defaultPdfPath, forKey: AppSettingsModel.defaultPdfPathKey)
        }
    }
    
    public var defaultPhotoLocation: Int = 0 {
        didSet {
            guard oldValue != defaultPhotoLocation else { return }
            UserDefaults.standard.set(defaultPhotoLocation, forKey: AppSettingsModel.defaultPhotoLocationKey)
        }
    }
    public var defaultPhotoPath: String? {
        didSet {
            guard oldValue != defaultPhotoPath else { return }
            UserDefaults.standard.set(defaultPhotoPath, forKey: AppSettingsModel.defaultPhotoPathKey)
        }
    }
    
    public var defaultSpaceLocation: Int = 0 {
        didSet {
            guard oldValue != defaultSpaceLocation else { return }
            UserDefaults.standard.set(defaultSpaceLocation, forKey: AppSettingsModel.defaultSpaceLocationKey)
        }
    }
    public var defaultSpacePath: String? {
        didSet {
            guard oldValue != defaultSpacePath else { return }
            UserDefaults.standard.set(defaultSpacePath, forKey: AppSettingsModel.defaultSpacePathKey)
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
    
    // MARK: - Init Settings
    
    private func initSettings() {
        firstLaunch = UserDefaults.standard.value(forKey: AppSettingsModel.firstLunchKey) as? Bool ?? true
        appColorScheme = AppColorScheme(rawValue: UserDefaults.standard.integer(forKey: AppSettingsModel.appColorSchemeKey)) ?? .system
        
        // shared App groups
        useCloudKit = UserDefaults.standard.bool(forKey: AppSettingsModel.useCloudKitKey)
        
        defaultAudioLocation = UserDefaults.standard.integer(forKey: AppSettingsModel.defaultAudioLocationKey)
        defaultAudioPath = UserDefaults.standard.string(forKey: AppSettingsModel.defaultAudioPathKey)

        defaultPdfLocation = UserDefaults.standard.integer(forKey: AppSettingsModel.defaultPdfLocationKey)
        defaultPdfPath = UserDefaults.standard.string(forKey: AppSettingsModel.defaultPdfPathKey)

        defaultPhotoLocation = UserDefaults.standard.integer(forKey: AppSettingsModel.defaultPhotoLocationKey)
        defaultPhotoPath = UserDefaults.standard.string(forKey: AppSettingsModel.defaultPhotoPathKey)
        
        defaultSpaceLocation = UserDefaults.standard.integer(forKey: AppSettingsModel.defaultSpaceLocationKey)
        defaultSpacePath = UserDefaults.standard.string(forKey: AppSettingsModel.defaultSpacePathKey)
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
