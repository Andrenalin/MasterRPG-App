// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import os.log

import AudioRPG
import PdfRPG
import PhotoRPG
import SpaceRPG

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    @MainActor
    static let bootStrap = Logger(subsystem: subsystem, category: "BootStrap")
}

@MainActor @Observable
public final class AppModel: Sendable {

    // DB
    public let modelContainer: ModelContainer

    // other models
    public let deviceRotationModel: DeviceRotationModel

    // Module roots
    public var audioRoot: AudioRootModel
    public var pdfRoot: PdfRootModel
    public var photoRoot: PhotoRootModel
    public var spaceRoot: SpaceRootModel

    // Routing models
    public var navigator: Navigator

    @MainActor
    public init() {
        self.deviceRotationModel = DeviceRotationModel()
        self.navigator = Navigator(configuration: NavigationConfiguration(restorationKey: "1.0.0", executionDelay: 0.4, verbosity: .info))
        let modelContainer = Self.initModelContainer()
        self.modelContainer = modelContainer
        self.audioRoot = AudioRootFactory.rootModel(modelContext: modelContainer.mainContext)
        self.pdfRoot = PdfRootFactory.rootModel(modelContext: modelContainer.mainContext)
        self.photoRoot = PhotoRootFactory.rootModel(modelContext: modelContainer.mainContext)
        self.spaceRoot = SpaceRootFactory.rootModel(modelContext: modelContainer.mainContext)
    }
    
    @MainActor
    private static func initModelContainer() -> ModelContainer {
        let schema = Schema(
            [
                TagDataModel.self,
                AudioDataModel.self,
                AudioEntryDataModel.self,
                PdfDataModel.self,
                PdfEntryDataModel.self,
                PhotoDataModel.self,
                PhotoEntryDataModel.self,
                SpaceDataModel.self,
                SpaceEntryDataModel.self,
            ]
        )
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true, groupContainer: .none, cloudKitDatabase: .private("icloud.de.andretrettin.MasterRPG"))
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
