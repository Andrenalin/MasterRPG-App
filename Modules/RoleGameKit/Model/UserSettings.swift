// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGAudios
import RPGSpaces
import RPGPhotos
import RPGPdfs

public struct UserSettingsViewModifier: ViewModifier {
    public init(appStore: AppStore) {
        self.appStore = appStore
        self.settingsModel = appStore.settingsModel
    }
    
    let appStore: AppStore
    let settingsModel: AppSettingsModel

    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
//            .onChange(of: settingsModel.defaultAudioLocation, initial: true) {
//                if appStore.audioRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultAudioLocation {
//                    appStore.audioRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: settingsModel.defaultAudioLocation) ?? .appCloud
//                }
//            }
//            .onChange(of: appStore.audioRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
//                if appStore.audioRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultAudioLocation {
//                    settingsModel.defaultAudioLocation = appStore.audioRoot.fileUrlDataController.model.defaultLoaction.id
//                }
//            }
//            .onChange(of: settingsModel.defaultAudioPath, initial: true) {
//                if let audioPathId = settingsModel.defaultAudioPath, appStore.audioRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: audioPathId) {
//                    appStore.audioRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: audioPathId)
//                }
//            }
//            .onChange(of: appStore.audioRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
//                if appStore.audioRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != settingsModel.defaultAudioPath {
//                    settingsModel.defaultAudioPath = appStore.audioRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
//                }
//            }
//            .onChange(of: settingsModel.defaultPdfLocation, initial: true) {
//                if appStore.pdfRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultPdfLocation {
//                    appStore.pdfRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: settingsModel.defaultPdfLocation) ?? .appCloud
//                }
//            }
//            .onChange(of: appStore.pdfRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
//                if appStore.pdfRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultPdfLocation {
//                    settingsModel.defaultPdfLocation = appStore.pdfRoot.fileUrlDataController.model.defaultLoaction.id
//                }
//            }
//            .onChange(of: settingsModel.defaultPdfPath, initial: true) {
//                if let pdfPathId = settingsModel.defaultPdfPath, appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: pdfPathId) {
//                    appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: pdfPathId)
//                }
//            }
//            .onChange(of: appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
//                if appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != settingsModel.defaultPdfPath {
//                    settingsModel.defaultPdfPath = appStore.pdfRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
//                }
//            }
//            .onChange(of: settingsModel.defaultPhotoLocation, initial: true) {
//                if appStore.photoRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultPhotoLocation {
//                    appStore.photoRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: settingsModel.defaultPhotoLocation) ?? .appCloud
//                }
//            }
//            .onChange(of: appStore.photoRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
//                if appStore.photoRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultPhotoLocation {
//                    settingsModel.defaultPhotoLocation = appStore.photoRoot.fileUrlDataController.model.defaultLoaction.id
//                }
//            }
//            .onChange(of: settingsModel.defaultPhotoPath, initial: true) {
//                if let photoPathId = settingsModel.defaultPhotoPath, appStore.photoRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: photoPathId) {
//                    appStore.photoRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: photoPathId)
//                }
//            }
//            .onChange(of: appStore.photoRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
//                if appStore.photoRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != settingsModel.defaultPhotoPath {
//                    settingsModel.defaultPhotoPath = appStore.photoRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
//                }
//            }
//            .onChange(of: settingsModel.defaultSpaceLocation, initial: true) {
//                if appStore.spaceRoot.fileUrlDataController!.model.defaultLoaction.id != settingsModel.defaultSpaceLocation {
//                    appStore.spaceRoot.fileUrlDataController!.model.defaultLoaction = FileLocation(rawValue: settingsModel.defaultSpaceLocation) ?? .appCloud
//                }
//            }
//            .onChange(of: appStore.spaceRoot.fileUrlDataController!.model.defaultLoaction, initial: false) {
//                if appStore.spaceRoot.fileUrlDataController!.model.defaultLoaction.id != settingsModel.defaultSpaceLocation {
//                    settingsModel.defaultSpaceLocation = appStore.spaceRoot.fileUrlDataController!.model.defaultLoaction.id
//                }
//            }
//            .onChange(of: settingsModel.defaultSpacePath, initial: true) {
//                if let spacePathId = settingsModel.defaultSpacePath, appStore.spaceRoot.fileUrlDataController!.model.defaultCloudPath != UUID(uuidString: spacePathId) {
//                    appStore.spaceRoot.fileUrlDataController!.model.defaultCloudPath = UUID(uuidString: spacePathId)
//                }
//            }
//            .onChange(of: appStore.spaceRoot.fileUrlDataController!.model.defaultCloudPath, initial: false) {
//                if appStore.spaceRoot.fileUrlDataController!.model.defaultCloudPath?.uuidString != settingsModel.defaultSpacePath {
//                    settingsModel.defaultSpacePath = appStore.spaceRoot.fileUrlDataController!.model.defaultCloudPath?.uuidString
//                }
//            }
#if os(iOS)
            .applyIf(settingsModel.appColorScheme != .system) {
                $0.environment(\.colorScheme, settingsModel.appColorScheme.colorScheme(for: colorScheme))
            }
#endif
    }
}
