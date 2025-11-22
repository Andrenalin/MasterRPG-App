// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGAudios
import SpaceRPG
import RPGPhotos
import RPGPdfs

public struct UserSettingsViewModifier: ViewModifier {
    public init(appModel: AppModel) {
        self.appModel = appModel
        self.settingsModel = appModel.settingsModel
    }
    
    let appModel: AppModel
    let settingsModel: AppSettingsModel

    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
//            .onChange(of: settingsModel.defaultAudioLocation, initial: true) {
//                if appModel.audioRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultAudioLocation {
//                    appModel.audioRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: settingsModel.defaultAudioLocation) ?? .appCloud
//                }
//            }
//            .onChange(of: appModel.audioRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
//                if appModel.audioRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultAudioLocation {
//                    settingsModel.defaultAudioLocation = appModel.audioRoot.fileUrlDataController.model.defaultLoaction.id
//                }
//            }
//            .onChange(of: settingsModel.defaultAudioPath, initial: true) {
//                if let audioPathId = settingsModel.defaultAudioPath, appModel.audioRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: audioPathId) {
//                    appModel.audioRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: audioPathId)
//                }
//            }
//            .onChange(of: appModel.audioRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
//                if appModel.audioRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != settingsModel.defaultAudioPath {
//                    settingsModel.defaultAudioPath = appModel.audioRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
//                }
//            }
//            .onChange(of: settingsModel.defaultPdfLocation, initial: true) {
//                if appModel.pdfRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultPdfLocation {
//                    appModel.pdfRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: settingsModel.defaultPdfLocation) ?? .appCloud
//                }
//            }
//            .onChange(of: appModel.pdfRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
//                if appModel.pdfRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultPdfLocation {
//                    settingsModel.defaultPdfLocation = appModel.pdfRoot.fileUrlDataController.model.defaultLoaction.id
//                }
//            }
//            .onChange(of: settingsModel.defaultPdfPath, initial: true) {
//                if let pdfPathId = settingsModel.defaultPdfPath, appModel.pdfRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: pdfPathId) {
//                    appModel.pdfRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: pdfPathId)
//                }
//            }
//            .onChange(of: appModel.pdfRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
//                if appModel.pdfRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != settingsModel.defaultPdfPath {
//                    settingsModel.defaultPdfPath = appModel.pdfRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
//                }
//            }
//            .onChange(of: settingsModel.defaultPhotoLocation, initial: true) {
//                if appModel.photoRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultPhotoLocation {
//                    appModel.photoRoot.fileUrlDataController.model.defaultLoaction = FileLocation(rawValue: settingsModel.defaultPhotoLocation) ?? .appCloud
//                }
//            }
//            .onChange(of: appModel.photoRoot.fileUrlDataController.model.defaultLoaction, initial: false) {
//                if appModel.photoRoot.fileUrlDataController.model.defaultLoaction.id != settingsModel.defaultPhotoLocation {
//                    settingsModel.defaultPhotoLocation = appModel.photoRoot.fileUrlDataController.model.defaultLoaction.id
//                }
//            }
//            .onChange(of: settingsModel.defaultPhotoPath, initial: true) {
//                if let photoPathId = settingsModel.defaultPhotoPath, appModel.photoRoot.fileUrlDataController.model.defaultCloudPath != UUID(uuidString: photoPathId) {
//                    appModel.photoRoot.fileUrlDataController.model.defaultCloudPath = UUID(uuidString: photoPathId)
//                }
//            }
//            .onChange(of: appModel.photoRoot.fileUrlDataController.model.defaultCloudPath, initial: false) {
//                if appModel.photoRoot.fileUrlDataController.model.defaultCloudPath?.uuidString != settingsModel.defaultPhotoPath {
//                    settingsModel.defaultPhotoPath = appModel.photoRoot.fileUrlDataController.model.defaultCloudPath?.uuidString
//                }
//            }
//            .onChange(of: settingsModel.defaultSpaceLocation, initial: true) {
//                if appModel.spaceRoot.fileUrlDataController!.model.defaultLoaction.id != settingsModel.defaultSpaceLocation {
//                    appModel.spaceRoot.fileUrlDataController!.model.defaultLoaction = FileLocation(rawValue: settingsModel.defaultSpaceLocation) ?? .appCloud
//                }
//            }
//            .onChange(of: appModel.spaceRoot.fileUrlDataController!.model.defaultLoaction, initial: false) {
//                if appModel.spaceRoot.fileUrlDataController!.model.defaultLoaction.id != settingsModel.defaultSpaceLocation {
//                    settingsModel.defaultSpaceLocation = appModel.spaceRoot.fileUrlDataController!.model.defaultLoaction.id
//                }
//            }
//            .onChange(of: settingsModel.defaultSpacePath, initial: true) {
//                if let spacePathId = settingsModel.defaultSpacePath, appModel.spaceRoot.fileUrlDataController!.model.defaultCloudPath != UUID(uuidString: spacePathId) {
//                    appModel.spaceRoot.fileUrlDataController!.model.defaultCloudPath = UUID(uuidString: spacePathId)
//                }
//            }
//            .onChange(of: appModel.spaceRoot.fileUrlDataController!.model.defaultCloudPath, initial: false) {
//                if appModel.spaceRoot.fileUrlDataController!.model.defaultCloudPath?.uuidString != settingsModel.defaultSpacePath {
//                    settingsModel.defaultSpacePath = appModel.spaceRoot.fileUrlDataController!.model.defaultCloudPath?.uuidString
//                }
//            }
#if os(iOS)
            .applyIf(settingsModel.appColorScheme != .system) {
                $0.environment(\.colorScheme, settingsModel.appColorScheme.colorScheme(for: colorScheme))
            }
#endif
    }
}
