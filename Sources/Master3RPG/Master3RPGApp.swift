//
//  Master3RPGApp.swift
//  Master3RPG
//
//  Created by Andre Trettin on 02.07.25.
//

import CoreRPG
import PhotoRPG
import SwiftUI
import SwiftData

@main
struct Master3RPGApp: App {
    @State private var appRootUiModel = AppRootUiModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var searchModel = SearchModel()
    @State private var cacheModel = CacheItemListModel()

    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PhotoDataModel.self, PhotoEntryDataModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(\.colorScheme, .dark)
                .environment(appRootUiModel)
                .environment(deviceRotationModel)
                .environment(searchModel)
                .environment(cacheModel)
                .frame(minWidth: 375.0, minHeight: 600.0)
                // Keeps the current window's size for use in scrolling header calculations.
                .onGeometryChange(for: CGSize.self) { geometry in
                    geometry.size
                } action: {
                    appRootUiModel.windowSize = $0
                }
                .tint(Color.teal)

        }
        .modelContainer(sharedModelContainer)
    }
}
