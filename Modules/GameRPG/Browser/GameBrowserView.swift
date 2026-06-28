//
//  GameBrowserView.swift
//  MasterRPG
//
//  Created by Andre Trettin on 16/6/2569 BE.
//

import SwiftUI
import Network

struct GameBrowserView: View {
    @State private var browserManager: BrowserManager = BrowserManager()

    var body: some View {
        VStack {
            if let errorMessage = browserManager.errorMessage {
                Text(errorMessage)
                Divider()
            }
            ForEach(browserManager.games) { game in
                Text("Got - \(game.deviceName)")
            }
        }
        .padding()
        .onAppear { browserManager.start() }
        .onDisappear { browserManager.stop() }
    }
}
