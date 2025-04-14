// @copyright André Trettin

import AndrenalinKit
import SwiftUI

public struct UserSettingsViewModifier: ViewModifier {
    public init(appStore: AppStore) {
        self.appStore = appStore
    }
    
    let appStore: AppStore
    
    @MainActor
    public static let useCloudKit = "MasterRPGuseCloudKit"
    @MainActor
    public static let firstLunch = "FirstLunchMasterRPG"
    
    @AppStorage("appColorScheme", store: .standard) private var appColorScheme: AppSettingsModel.AppColorScheme = .system

    @AppStorage(UserSettingsViewModifier.useCloudKit, store: .standard)
    private var useCloudKit: Bool = false

    @AppStorage(UserSettingsViewModifier.firstLunch, store: .standard)
    private var firstLunch: Bool = true

    @AppStorage("defaultAudioLocation", store: .standard)
    private var audioLocation: Int = 0
    @AppStorage("defaultAudioPath", store: .standard)
    private var audioPathId: String?
    
    @AppStorage("defaultPdfLocation", store: .standard)
    private var pdfLocation: Int = 0
    @AppStorage("defaultPdfPath", store: .standard)
    private var pdfPathId: String?

    @AppStorage("defaultPhotoLocation", store: .standard)
    private var photoLocation: Int = 0
    @AppStorage("defaultPhotoPath", store: .standard)
    private var photoPathId: String?

    @AppStorage("defaultSpaceLocation", store: .standard)
    private var spaceLocation: Int = 0
    @AppStorage("defaultSpacePath", store: .standard)
    private var spacePathId: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var colorSaved: Bool = false

    public func body(content: Content) -> some View {
        content
            .onChange(of: audioLocation, initial: true) {
                if appStore.audioRoot.fileUrlDataController.model.defaultLoaction.id != audioLocation {
                    appStore.audioRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: audioLocation) ?? .appCloud
                }
            }
            .onChange(of: appStore.audioRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
                if appStore.audioRoot.fileUrlDataController.model.defaultLoaction.id != audioLocation {
                    audioLocation = appStore.audioRoot.fileUrlDataController.model.defaultLoaction.id
                }
            }
            .onChange(of: audioPathId, initial: true) {
                if let audioPathId, appStore.audioRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: audioPathId) {
                    appStore.audioRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: audioPathId)
                }
            }
            .onChange(of: appStore.audioRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
                if appStore.audioRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != audioPathId {
                    audioPathId = appStore.audioRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
                }
            }
            .onChange(of: pdfLocation, initial: true) {
                if appStore.pdfRoot.fileUrlDataController.model.defaultLoaction.id != pdfLocation {
                    appStore.pdfRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: pdfLocation) ?? .appCloud
                }
            }
            .onChange(of: appStore.pdfRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
                if appStore.pdfRoot.fileUrlDataController.model.defaultLoaction.id != pdfLocation {
                    pdfLocation = appStore.pdfRoot.fileUrlDataController.model.defaultLoaction.id
                }
            }
            .onChange(of: pdfPathId, initial: true) {
                if let pdfPathId, appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: pdfPathId) {
                    appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: pdfPathId)
                }
            }
            .onChange(of: appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
                if appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != pdfPathId {
                    pdfPathId = appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
                }
            }
            .onChange(of: photoLocation, initial: true) {
                if appStore.photoRoot.fileUrlDataController.model.defaultLoaction.id != photoLocation {
                    appStore.photoRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: photoLocation) ?? .appCloud
                }
            }
            .onChange(of: appStore.photoRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
                if appStore.photoRoot.fileUrlDataController.model.defaultLoaction.id != photoLocation {
                    photoLocation = appStore.photoRoot.fileUrlDataController.model.defaultLoaction.id
                }
            }
            .onChange(of: photoPathId, initial: true) {
                if let photoPathId, appStore.photoRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: photoPathId) {
                    appStore.photoRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: photoPathId)
                }
            }
            .onChange(of: appStore.photoRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
                if appStore.photoRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != photoPathId {
                    photoPathId = appStore.photoRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
                }
            }
            .onChange(of: spaceLocation, initial: true) {
                if appStore.spaceRoot.fileUrlDataController.model.defaultLoaction.id != spaceLocation {
                    appStore.spaceRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: spaceLocation) ?? .appCloud
                }
            }
            .onChange(of: appStore.spaceRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
                if appStore.spaceRoot.fileUrlDataController.model.defaultLoaction.id != spaceLocation {
                    spaceLocation = appStore.spaceRoot.fileUrlDataController.model.defaultLoaction.id
                }
            }
            .onChange(of: spacePathId, initial: true) {
                if let spacePathId, appStore.spaceRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: spacePathId) {
                    appStore.spaceRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: spacePathId)
                }
            }
            .onChange(of: appStore.spaceRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
                if appStore.spaceRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != spacePathId {
                    spacePathId = appStore.spaceRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
                }
            }
            .onChange(of: useCloudKit, initial: true) {
                appStore.settingsModel.useCloudKit <=> useCloudKit
            }
            .onChange(of: appStore.settingsModel.useCloudKit, initial: false) {
                if appStore.settingsModel.useCloudKit != useCloudKit {
                    useCloudKit = appStore.settingsModel.useCloudKit
                }
            }
            .onChange(of: firstLunch, initial: true) {
                appStore.firstLunch <=> firstLunch
            }
            .onChange(of: appStore.firstLunch, initial: false) {
                if appStore.firstLunch != firstLunch {
                    firstLunch = appStore.firstLunch
                }
            }
#if os(iOS)
            .onChange(of: appStore.settingsModel.appColorScheme) {
                guard colorSaved else { return }
                appColorScheme <=> appStore.settingsModel.appColorScheme
            }
            .onAppear {
                appStore.settingsModel.appColorScheme <=> appColorScheme
                colorSaved = true
            }
            .applyIf(appColorScheme != .system) {
                $0.environment(\.colorScheme, appColorScheme.colorScheme(for: colorScheme))
            }
#endif
    }
}
