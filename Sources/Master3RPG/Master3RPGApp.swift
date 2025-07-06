//
//  Master3RPGApp.swift
//  Master3RPG
//
//  Created by Andre Trettin on 02.07.25.
//

import SwiftUI
import SwiftData

@main
struct Master3RPGApp: App {
    @State private var appRootModel = AppRootModel()
    
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
                .environment(appRootModel)
                .environment(appRootModel.deviceRotationModel)
                .environment(appRootModel.listModel)
                .frame(minWidth: 375.0, minHeight: 600.0)
                // Keeps the current window's size for use in scrolling header calculations.
                .onGeometryChange(for: CGSize.self) { geometry in
                    geometry.size
                } action: {
                    appRootModel.windowSize = $0
                }
                .tint(Color.teal)

        }
        .modelContainer(sharedModelContainer)
    }
}
