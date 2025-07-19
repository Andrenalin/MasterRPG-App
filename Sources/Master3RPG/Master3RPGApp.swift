//
//  Master3RPGApp.swift
//  Master3RPG
//
//  Created by Andre Trettin on 02.07.25.
//

import CoreRPG
import RolePlayGameKit
import SwiftUI
import SwiftData

@main
struct Master3RPGApp: App {
    @State private var appModel = AppModel()
    
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(\.colorScheme, .dark)
                .environment(appModel)
                .frame(minWidth: 375.0, minHeight: 600.0)
                // Keeps the current window's size for use in scrolling header calculations.
//                .onGeometryChange(for: CGSize.self) { geometry in
//                    geometry.size
//                } action: {
//                    appRootUiModel.windowSize = $0
//                }
                .tint(Color.teal)

        }
        .modelContainer(appModel.sharedModelContainer)
    }
}
