//
//  Master3RPGApp.swift
//  Master3RPG
//
//  Created by Andre Trettin on 02.07.25.
//

import AppIntents
import CoreRPG
import RolePlayGameKit
import SwiftUI
import SwiftData

@main
struct Master3RPGApp: App {
    @State private var appModel = AppModel()
    
    init() {
        let data = appModel
        AppDependencyManager.shared.add(dependency: data)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(\.colorScheme, .dark)
                .environment(appModel)
                .frame(minWidth: 375.0, minHeight: 600.0)
                .tint(Color.teal)

        }
        .modelContainer(appModel.modelContainer)
    }
}
