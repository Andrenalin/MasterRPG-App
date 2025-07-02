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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
